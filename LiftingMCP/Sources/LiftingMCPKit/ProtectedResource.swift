import Foundation

/// Where a client is sent to find out how to authenticate, and what it gets
/// when it goes there.
///
/// **What it does.** Holds this server's identity as an OAuth 2.1 protected
/// resource — its canonical URI and the authorization servers that issue tokens
/// for it — and produces the two things RFC 9728 defines: the metadata document,
/// and the `WWW-Authenticate` challenge that points at it.
///
/// **Why it is required rather than nice.** The MCP specification says an
/// HTTP-transport server *"**MUST** implement OAuth 2.0 Protected Resource
/// Metadata"* and that clients *"**MUST** use"* it to discover the authorization
/// server. A bare `WWW-Authenticate: Bearer` — which is what this server sent
/// before — tells a client it was refused and nothing about how to come back,
/// so a connector cannot complete a flow it has no way to begin.
///
/// **How it is used.** `HTTPEndpoint` serves `metadata` unauthenticated and puts
/// `challenge` on every 401. Both are derived from one value, so the address a
/// client is sent to and the address that answers cannot disagree.
///
/// **What it depends on.** `JSONValue` and Foundation. It issues nothing,
/// validates nothing, and knows no secrets: it is the sign on the door.
public struct ProtectedResource: Sendable {

    /// This server's canonical URI, which is what a token must be audienced to.
    ///
    /// The MCP specification asks for the most specific URI the client will
    /// actually call, with no fragment and no trailing slash — `https://host/mcp`
    /// rather than `https://host`.
    public let resource: URL

    /// Who issues tokens for it. Colocated for one user, and deliberately a list
    /// because RFC 9728 says so and because a second issuer is a configuration
    /// change rather than a code change.
    public let authorizationServers: [URL]

    /// What a token must carry to reach the tools.
    ///
    /// **One scope, because one scope is enforced.** The specification invites a
    /// least-privilege split — reading the log is not prescribing into it — and
    /// that split is worth making. It is not made *here* yet, because declaring
    /// a `training:write` this server never checks would be a schema promising
    /// behaviour the code does not have, which is the exact defect this project
    /// has spent the week removing. It gets published when it gets checked.
    public static let scope = "training"

    public init(resource: URL, authorizationServers: [URL]) {
        self.resource = resource
        self.authorizationServers = authorizationServers
    }

    /// The paths that serve the metadata document.
    ///
    /// **Two, and both on purpose.** RFC 9728 forms the URL by inserting
    /// `/.well-known/oauth-protected-resource` *before* the resource's path, so
    /// a resource at `/mcp` publishes at
    /// `/.well-known/oauth-protected-resource/mcp`. The MCP specification's own
    /// example shows the bare path, because its example resource is a host root.
    /// Clients in the wild try both, the document is identical either way, and
    /// discovery that fails is worse than an address served twice — this is the
    /// one place in this server where being liberal beats refusing, because
    /// there is nothing here to get wrong and nothing to take in.
    public var metadataPaths: [String] {
        let base = "/.well-known/oauth-protected-resource"
        let path = resource.path()
        return path.isEmpty || path == "/" ? [base] : [base + path, base]
    }

    /// The metadata document, as RFC 9728 defines it.
    public var metadata: JSONValue {
        [
            "resource": .string(resource.absoluteString),
            "authorization_servers": .array(
                authorizationServers.map { .string($0.absoluteString) }),
            "scopes_supported": [.string(Self.scope)],
            // The header, and only the header. A token in a query string lands
            // in every proxy log between here and the client.
            "bearer_methods_supported": ["header"],
        ]
    }

    /// The `WWW-Authenticate` value for a 401.
    ///
    /// Carries `resource_metadata` so a client can discover the issuer, and
    /// `scope` so it knows what to ask for — which the specification says a
    /// server **SHOULD** do, so that a client requests what it needs and not
    /// everything.
    public var challenge: String {
        return #"Bearer resource_metadata="\#(metadataURL.absoluteString)", scope="\#(Self.scope)""#
    }

    /// Where the metadata document lives, built from components rather than by
    /// editing the string.
    ///
    /// Cutting a path out of an absolute URL by substring replacement is how a
    /// host called `mcp` loses part of its name. The fallback returns the
    /// resource itself, which is wrong but reachable — a client following it
    /// gets a 404 it can report, where a crash or an empty string gives it
    /// nothing to say.
    public var metadataURL: URL {
        var components = URLComponents(url: resource, resolvingAgainstBaseURL: false)
        components?.path = metadataPaths[0]
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? resource
    }
}
