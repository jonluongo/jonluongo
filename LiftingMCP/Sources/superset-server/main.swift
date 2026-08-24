import Foundation
import LiftingKit
import LiftingMCPKit
import NIOCore
import NIOHTTP1
import NIOPosix

// The HTTP shell: it pumps bytes and holds no rules.
//
// `HTTPEndpoint` decides every one of them — path, method, credential, what a
// refusal answers with — and is tested without a socket. This file exists to
// open the port and hand it whole requests, which is the same division
// `lifting-mcp` has with `MCPServer`. If a rule ever appears in this file, it
// is in the wrong file.

/// Reads whole requests off one connection and answers each with the endpoint.
///
/// **The body arrives in pieces and the endpoint wants it whole**, so parts are
/// gathered until `.end` before anything is decided. NIO's HTTP/1.1 codec has
/// already handled chunking, keep-alive and header casing by the time anything
/// reaches here.
/// **`@unchecked Sendable`, and the pipeline is what makes that true.** A
/// channel handler is created per connection and touched only on the event loop
/// that owns its channel, so the mutable `head` and `body` below are never seen
/// by two threads — but the compiler cannot know that from the type, and NIO's
/// own handlers carry the same annotation for the same reason. The alternative
/// is a lock around state that is already confined, which would buy nothing and
/// suggest a sharing that does not happen.
private final class Handler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let endpoint: HTTPEndpoint
    private var head: HTTPRequestHead?
    private var body = ByteBuffer()

    init(endpoint: HTTPEndpoint) {
        self.endpoint = endpoint
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            body.clear()
        case .body(var part):
            body.writeBuffer(&part)
        case .end:
            guard let head else { return }
            answer(head, in: context)
            self.head = nil
            body.clear()
        }
    }

    private func answer(_ head: HTTPRequestHead, in context: ChannelHandlerContext) {
        // **The path is taken without its query.** A credential must never
        // arrive in a query string — it lands in every proxy log on the way —
        // and this is also what stops `/mcp?x=1` reading as a path the endpoint
        // does not serve.
        let path = String(head.uri.prefix(while: { $0 != "?" }))
        let headers = Dictionary(
            head.headers.map { ($0.name.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last })

        let answer = endpoint.response(
            method: head.method.rawValue, path: path, headers: headers,
            body: body.getString(at: body.readerIndex, length: body.readableBytes) ?? "")

        var responseHeaders = HTTPHeaders()
        for (name, value) in answer.headers { responseHeaders.add(name: name, value: value) }
        let bytes = Array(answer.body.utf8)
        responseHeaders.add(name: "content-length", value: String(bytes.count))

        context.write(
            wrapOutboundOut(.head(HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus(statusCode: answer.status),
                headers: responseHeaders))), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}

/// One shared secret, compared in constant time.
///
/// **The interface, not the issuer.** What mints a credential is a separate
/// question — see `server-spec.md` — and `HTTPEndpoint.Authorization` is the
/// seam that lets it change without touching a rule. What is settled here is
/// that the server *demands* one, and that a server started without a secret
/// refuses everything rather than serving a stranger's plans openly.
private struct SharedSecret: HTTPEndpoint.Authorization {

    let secret: String

    func permits(headers: [String: String]) -> Bool {
        guard !secret.isEmpty, let offered = headers["authorization"] else { return false }
        // **Constant time, because a shared secret leaks through a fast `==`.**
        // Comparing byte by byte and returning early tells a caller how much of
        // its guess was right, and a few thousand guesses turn that into the
        // secret. This costs nothing and removes the question.
        let expected = Array("Bearer \(secret)".utf8)
        let given = Array(offered.utf8)
        guard expected.count == given.count else { return false }
        return zip(expected, given).reduce(into: UInt8(0)) { $0 |= $1.0 ^ $1.1 } == 0
    }
}

// MARK: - Starting up

let environment = ProcessInfo.processInfo.environment

// **Refuses to start rather than starting open.** A server that comes up
// without a secret and serves anyway is the failure that looks like success:
// everything works, and anyone who finds the URL can read the training log and
// prescribe into it.
guard let secret = environment["SUPERSET_TOKEN"], !secret.isEmpty else {
    FileHandle.standardError.write(Data("""
        superset-server needs SUPERSET_TOKEN — the credential every request must \
        present as 'Authorization: Bearer <token>'. It will not start without one, \
        because a server with no credential serves this training log to anyone who \
        finds it.

        """.utf8))
    exit(78)  // EX_CONFIG
}

let configuration = try ServerConfiguration.resolve(
    arguments: CommandLine.arguments, environment: environment, home: URL.homeDirectory)
let documents = DocumentFolder(directory: configuration.documentsDirectory)
// **The OAuth identity, published only when there is an issuer to name.**
// `SUPERSET_URL` is the address a client actually calls — Fly's
// `https://<app>.fly.dev/mcp` — and `SUPERSET_AUTH_SERVER` is whoever issues
// tokens for it. Both or neither: a resource without an issuer has nowhere to
// send a client, and an issuer without the resource's own canonical URI cannot
// audience a token to it. Set neither and the server runs on the shared secret
// and says so, rather than advertising a flow nobody can finish.
let resource: ProtectedResource? = {
    guard let site = environment["SUPERSET_URL"].flatMap(URL.init(string:)),
        let issuer = environment["SUPERSET_AUTH_SERVER"].flatMap(URL.init(string:))
    else { return nil }
    return ProtectedResource(resource: site, authorizationServers: [issuer])
}()

let endpoint = HTTPEndpoint(
    server: MCPServer(runner: ToolRunner(
        documents: documents, catalog: try ExerciseCatalog.bundled())),
    authorization: SharedSecret(secret: secret),
    resource: resource)

// The port is the platform's to choose: Fly sets `PORT` and routes to it.
let port = environment["PORT"].flatMap(Int.init) ?? 8080
let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(Handler(endpoint: endpoint))
        }
    }
    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
// Says which mode it came up in, because "it started" is not the same as "it is
// doing what you think", and the difference here is whether a connector can
// discover how to authenticate at all.
let discovery = resource.map { "OAuth discovery at \($0.metadataURL.absoluteString)" }
    ?? "shared secret only — set SUPERSET_URL and SUPERSET_AUTH_SERVER to publish OAuth discovery"
FileHandle.standardError.write(Data("""
    superset-server listening on \(port)
      documents: \(configuration.documentsDirectory.path)
      auth:      \(discovery)

    """.utf8))
try channel.closeFuture.wait()
