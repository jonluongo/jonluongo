import Foundation

/// The coach's two markdown notes, by name.
///
/// **What it does.** Names `ACCOUNT.md` and `PROGRAM.md` in one place, so the
/// phone and the server cannot disagree about which file is which — the same
/// reason `DocumentFolder` names `plan.json` once.
///
/// **The line between them: would this still be true if the routine were thrown
/// out tomorrow?** Yes, and it is the account — that file is the person. No, and
/// it is the program — that file is the routine. It is why the objective and the
/// equipment sit in the program rather than the account: a goal is the design
/// brief and equipment is the constraint selection is drawn against. Neither is
/// a fact about the body.

/// **Every heading is a plain noun phrase**, sentence case, no article and no
/// pronoun — *Constraints*, *Progression*, *Schedule and equipment*. They were
/// three grammatical shapes at once (*Recovery*, *The approach*, *What he has to
/// work with*), which reads as three authors. A heading names a section; it does
/// not address anybody.
///
/// **Both are slim on purpose, because the tables hold the rest.** Every
/// prescribed and performed set is a row, so sets per muscle per week, load
/// progression, prescribed-versus-performed intensity and every exercise's
/// history are *computed* — `volume_by_muscle` and `exercise_history` exist
/// precisely so none of that is written down twice. What is left in prose is
/// only what no table can hold and what actually changes the next block.
///
/// **Neither is ever parsed.** The app renders them. The moment a value has to
/// come back out, that value belongs in a table.
public enum NoteFile: String, Sendable, CaseIterable {
    case account
    case program

    /// Upper-case on disk, the way a repository names the files a reader is
    /// meant to open first. The raw value stays lower-case because it is a Swift
    /// case name and a coding key.
    public var basename: String { rawValue.uppercased() }

    public var filename: String { "\(basename).md" }

    /// What an unwritten note says, and what the coach edits beneath.
    ///
    /// **It starts at the first section, not at a title.** The sheet that draws
    /// this is already named; a heading repeating it is the screen saying the
    /// same thing twice.
    ///
    /// **An empty file gives an anchored edit nothing to anchor to.** The
    /// headings are the anchors: `update_notes` states the text it expects to
    /// replace, so the coach's first write needs something already there to
    /// replace. It is also what the app draws before the coach has written
    /// anything — a record that has been told nothing must read as *not known*,
    /// never as a plausible default.
    ///
    /// **One condition, one sentence.** The five account sections said *None on
    /// record*, *Not yet stated* and *Nothing on record* for the identical
    /// state — nothing written — and rendered together they read as three
    /// different states with a difference the reader goes looking for and does
    /// not find. `PROGRAM.md` already said one thing five times; both notes say
    /// it now. That the line repeats is not an obstacle to editing it: an
    /// anchored edit quotes the heading with the line under it, which is what
    /// `update_notes` asks for and what makes each one unique.
    public var template: String {
        switch self {
        case .account:
            """
            ## Constraints
            _Not yet stated._

            ## Background
            _Not yet stated._

            ## Other activity
            _Not yet stated._

            ## Recovery
            _Not yet stated._

            ## Technique notes
            _Not yet stated._
            """
        case .program:
            """
            ## Objective
            _Not yet stated._

            ## Schedule and equipment
            _Not yet stated._

            ## Approach
            _Not yet stated._

            ## Progression
            _Not yet stated._

            ## Monitoring
            _Not yet stated._
            """
        }
    }

    /// What the section is for, in one sentence — handed to the coach by
    /// `update_notes` so he is told what belongs where rather than guessing from
    /// a heading.
    ///
    /// **Every one of these is something no table can answer.** The account's
    /// side is what the app is structurally blind to: it sees the sets logged in
    /// it and nothing else, so someone playing football twice a week looks
    /// exactly like someone who does not. The program's side is what the coach
    /// decided and must not re-decide from scratch every block.
    public var guidance: String {
        switch self {
        case .account:
            """
            Constraints — injuries, pain, surgeries, anything that must not be \
            trained, and why. This is the one thing that changes exercise \
            selection outright. Background — how long they have trained and on \
            what, which sets how fast they can be progressed, plus bodyweight. \
            Other activity — sport, physical work, training done elsewhere. The \
            app sees only the sets logged in it, so this is invisible to it and \
            it changes how much there is to recover from. Recovery — sleep, \
            stress, nutrition: the things that move strength 15-20% week to \
            week and explain a block that went badly. Technique notes — \
            standing notes about a movement, which survive a block being \
            rewritten.
            """
        case .program:
            """
            Objective — what this training is for. Schedule and equipment — \
            days a week, how long a session runs, what is available to train \
            with. Approach — the split, and how a block is shaped. Progression \
            — what advances week to week, which scale intensity is prescribed \
            on (RPE, RIR or percent of a max), where the volume ceiling sits, \
            and when a block deloads. Monitoring — the signals that change the \
            plan before the block ends.
            """
        }
    }
}
