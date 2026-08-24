# The server the phone talks to

> **Status: proposed. One piece built — `HTTPEndpoint`, step 2's first half.**
> Everything else here is still a proposal, and **auth is waiting on Jon**.
> Written 2026-08-24 after Jon's call that
> the destination is phone-only — Claude on the phone, Superset on the phone,
> the Mac disposable. Read `decided.md` first; this supersedes nothing in it
> except the transport.

## Why

The MCP server speaks stdio, so Claude Desktop launches it as a child process.
Claude on a phone cannot launch a binary — it reaches a server over HTTPS. That
one detail is the only reason a Mac was ever in the loop.

The Mac then turned out not to work either: macOS will not sync a ubiquity
container for an app that is not installed on that Mac, proven on 2026-08-24
with 160 GB of quota free and a file that still would not upload. **Both
problems have the same fix, and it is not a better use of iCloud.**

## What it is

```
Claude iOS  ──HTTPS──►  Superset server  ◄──HTTPS──  Superset app
                        holds the record,
                        the plan, the notes
```

iCloud leaves the loop entirely, and with it the container, the quota, the
`NSMetadataQuery` watcher, the upload-failure reporting, and the whole
*written is not delivered* failure class.

## What already fits, and what has to be written

**The protocol core does not change.** `MCPServer.handle(line:)` is documented
as *"a pure function from one line in to at most one line out. It touches no
file handles."* That is 281 lines that stay exactly as they are; the 81-line
stdio shell is what gets replaced.

**Both ends already read through protocol seams**, so this is replacement
rather than unpicking: the server through `TrainingDocuments`, the app through
`DocumentTransport`.

**Both packages are Linux-clean by construction, checked rather than assumed.**
`LiftingKit` and `LiftingMCPKit` import nothing but Foundation and each other;
every ubiquity call and `NSMetadataQuery` lives in `LiftingPlan/Services/`,
which is the app target and does not ship to the server. The layering rule is
what makes this true, and it is worth saying out loud that it paid for itself
here.

| Piece | Work |
|---|---|
| `MCPServer` and every tool | **None.** |
| stdio shell | Replaced by an HTTP shell: one POST endpoint that hands the body to `handle(line:)` and returns the answer. |
| `TrainingDocuments` conformance | **None — checked 2026-08-24.** `DocumentFolder` already conforms, in an extension in `LiftingMCPKit`; its directory is *injected* rather than resolved, so a volume path is just an argument; every Foundation call it makes (`contentsOfDirectory`, `createDirectory`, `fileExists`, atomic writes) is Linux-safe; and `DocumentTransportTests` already exercises it against a plain temp directory, which is what a volume is. `ServerConfiguration` already takes the path by `--documents` or `LIFTINGPLAN_DOCUMENTS_DIR`. |
| App's `DocumentTransport` | New HTTP conformance replacing `ICloudDocumentTransport`. |
| `UbiquitousDocumentWatcher` | **Deleted.** A watcher exists because iCloud arrives whenever it likes; the phone can ask. |
| Arrival model | The app polls on foreground and after finishing, instead of being told. |

## Hosting

**Fly.io.** Official Swift images, a persistent volume the file-based
conformance can use as-is, automatic HTTPS on `<name>.fly.dev` — which the
connector requires — and scale-to-zero at roughly $0–3/month for one user.
Rejected: Render's free tier spins down ~50s, which is unusable for interactive
tool calls; Cloudflare Workers has no Swift and would throw away the verified
core; Lambda and a VPS are both more moving parts than one user needs.

**Prove it on the Mac first, for nothing.** A Cloudflare Tunnel or Tailscale
Funnel over a locally-run server gives a real HTTPS URL and tests the whole
connector path before any hosting exists. A sleeping Mac is a dead connector,
so this is a proving step and never the destination.

## The one thing to get right rather than fast

**Auth.** Fly gives HTTPS, not authorisation. Without it that URL is a
stranger's training log, readable and writable, and `write_plan` would let
anyone prescribe. This is the only genuinely new thinking in the project —
everything else is moved rather than invented.

The shape is not decided. What matters:

- **Two clients, not one.** Claude reaches it as an MCP connector; the app
  reaches it as an ordinary HTTPS client. They may not deserve the same
  credential, and the app's can be stored in the keychain where Claude's cannot.
- **A bearer token is the cheap answer** and is probably enough for one user
  with a URL nobody knows — but *probably enough* is how the iCloud assumption
  got made, so it should be a decision rather than a default.
- **OAuth is what Claude's custom connectors are built for**, and it is more
  work.
- **The app must never ask the user for a token in a form.** The app asks the
  user nothing — that rule is not suspended for this. A credential arrives some
  other way or the rule needs an explicit exception, argued and recorded.

## What must not regress

Everything verified this week is above the transport and survives it untouched:
the plan and snapshot formats, every refusal, the counted-held-or-carried rule,
and all six tools. **The round-trip suite is the guard** — if
`PlanDocument(reconstructing:)` still round-trips after the transport changes,
the record is intact.

Two rules bind the new code as much as the old. **The phone stays the only
writer of the record**, so the server accepts a snapshot and never edits one.
And **a refusal is answered to its author** — `refused` in the snapshot is how
the phone tells the coach it turned a plan away, and an HTTP transport must
carry it as faithfully as a file did.

## Order

1. Confirm the Linux build for real, in Fly's remote builder — free, and the
   one fact still assumed rather than checked. **Two things to watch when it
   runs, both narrow.** `ISO8601DateFormatter` with `.withFractionalSeconds`
   names the kept copy of a note; it is not on any wire, so a Linux difference
   costs a filename and not a document. And the catalog resolves through
   `Bundle.module`, which SwiftPM generates on Linux too — `CatalogIntegrityTests`
   exists precisely because a resource that fails to resolve looks like an empty
   catalog rather than an error, so **running the package suites on Linux is the
   check**, not just building them.
2. ~~HTTP shell for the server~~ **Done.** The stdio shell stays for local work.
   Split in two on purpose (`HTTPEndpoint` + `superset-server`): every rule
   about what a client may send and what comes back is decided and tested with
   no socket, so the library that eventually opens the port inherits no
   decisions. **That library is the project's first external dependency and is
   not mine to choose** — `MCPServer`'s own comment rejects the official SDK for
   bringing five packages "into a project that otherwise has none", while naming
   the condition to revisit: *if the surface ever grows past this file*. Going
   from a local tool to a hosted server is that condition. The candidates are
   **Settled on swift-nio, against the first recommendation, on measurement.**
   Hummingbird was recommended believing its graph was small; resolved, it is
   **24 packages** — TLS, HTTP/2, certificates, ASN.1, crypto, an HTTP *client*,
   tracing, metrics — for one POST endpoint behind a proxy that already
   terminates TLS. swift-nio with `NIOHTTP1` is **4**, all from `apple/`, which
   is fewer than the five that got the MCP SDK rejected, and the HTTP/1.1 codec
   comes with it so nothing parses HTTP by hand. **It is confined to the
   `superset-server` target**: `LiftingMCPKit` and `LiftingKit` still link
   nothing third-party, so the whole tested core stays portable.
3. ~~Server-side `TrainingDocuments` on a volume.~~ **Done, by already being
   done** — see the table. It is configuration, not code.
4. **Auth: settled 2026-08-24 by reading the specs rather than choosing.**
   The MCP specification makes authorization **OPTIONAL**, and says an
   HTTP-transport server that does it **SHOULD** conform to OAuth 2.1 — server
   as resource server, RFC 9728 protected-resource metadata, PKCE, resource
   indicators. Anthropic's own connector documentation names **OAuth** as the
   method and mentions no static token or custom header. So the client decides
   this, not taste: **Claude → server is OAuth 2.1**, minimally implemented and
   colocated, because for one user the *authorisation* step is trivial while the
   *protocol* has to be real. **App → server stays the bearer token**, which is
   not MCP, has one client, and keeps its credential in the keychain.
   `HTTPEndpoint.Authorization` already lets both live side by side.

   **Blocked on a fact, not a decision.** Anthropic lists custom connectors on
   *"Claude, Cowork, and Claude Desktop"* and does not mention iOS. That is
   probably loose wording — connectors set up on claude.ai generally appear in
   the app — but it is load-bearing for the whole point of this, and building an
   authorisation server against a client that cannot reach it would repeat the
   Mac exactly. **Jon can settle it in thirty seconds** by looking for *Add
   custom connector* in the iOS app's Connectors settings; nothing here should
   be built until he has.

   *(Superseded: the interface below is still right and still built.)*

4b. **What was already settled and built.** Every request must
   present `Authorization: Bearer <token>`, compared in constant time, and
   **the server exits rather than starting without a secret** — a server that
   comes up open is the failure that looks like success. What *mints* the token
   is still open, and `HTTPEndpoint.Authorization` is the seam that lets it
   change without touching a rule. The app's bootstrap is the unsolved half:
   a secret baked into the binary is not acceptable, and the app asks the user
   nothing about training — a one-time sign-in is a different category and is
   the exception to argue for when it comes to that.
5. The app's HTTP transport, and delete what iCloud leaves behind.
6. Register the connector, and run the loop end to end from the phone.
