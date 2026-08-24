# The server the phone talks to

> **Status: proposed, nothing built.** Written 2026-08-24 after Jon's call that
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
| `TrainingDocuments` conformance | A directory on a Fly volume. `DocumentFolder` is already exactly this and may port unchanged. |
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
   one fact still assumed rather than checked.
2. HTTP shell for the server; the stdio one stays for local work.
3. Server-side `TrainingDocuments` on a volume.
4. **Auth, once Jon has ruled.**
5. The app's HTTP transport, and delete what iCloud leaves behind.
6. Register the connector, and run the loop end to end from the phone.
