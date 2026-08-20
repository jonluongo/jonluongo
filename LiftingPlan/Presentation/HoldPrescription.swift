import Foundation
import LiftingKit

/// What a prescribed hold puts into a set the app creates.
///
/// **What it does.** Answers one question: what a new row is seeded with when
/// the work is held for time. It is `RepPrescription`'s mirror, and between them
/// a prescribed target reaches the lifter as the unit it was written in.
///
/// It answered a second — *is this timed at all* — as a one-line forward to
/// `WorkDuration`. That question moved to `WorkPrescription`, which gives the
/// single `WorkMeasure` everything downstream binds to, and the forward stayed
/// behind with no caller in the app or in a test. A wrapper nobody calls, over a
/// property anyone can reach, is a second place to ask a question that must have
/// one answer.
///
/// **How it is used.** `SetSeeding` asks `seededSeconds` when it lays out the
/// rows for a session. A hold whose text names one duration is seeded with it,
/// exactly as a rep target naming one number is; a range seeds nothing, because
/// choosing an end of it would be the app deciding how long to hold.
///
/// **What it depends on.** `WorkDuration` from LiftingKit, which does the
/// reading. It decides nothing about training: an exercise is timed because its
/// prescription says so, never because of anything the lifter did.
enum HoldPrescription {

    /// The hold to seed into a new set, in seconds, or `nil` when the
    /// prescription names no single duration — a range, or no target at all.
    static func seededSeconds(for target: String?) -> Int? {
        WorkDuration(target ?? "").seconds
    }
}
