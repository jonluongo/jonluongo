import Foundation

/// The mark a session carries in a list, chosen by whoever wrote the plan.
///
/// **What it does.** Names one of a closed set of marks the app can draw. The
/// app owns the set and refuses anything outside it; the coach chooses which one
/// a session gets, exactly as he chooses its exercises from a catalog he did not
/// write. Nothing here infers a mark from a session's name or its movements —
/// that would be the app deciding what a session is about from words it does not
/// control, which is the reason day rows carried no icon at all until now.
///
/// **How it is used.** `PlanDocumentDay.icon` carries it in, `WorkoutDay` stores
/// the raw name, the snapshot carries the document back out so the coach can see
/// what he chose last time, and `RoutineView` draws it. The name is the app's own —
/// `strength`, `intervals` — never the system symbol behind it: which glyph a
/// name resolves to is this app's business, and changing one must not be a
/// change to the format the coach writes.
///
/// **Why a closed set rather than a free string.** A mark the app cannot draw is
/// not a mark; accepting one would mean silently drawing nothing, which is the
/// failure `DocumentRefusal` exists to prevent. `PlanImporter` refuses an
/// unknown name and says which it was, the same way it refuses an unknown
/// `ExerciseID`.
///
/// **What it depends on.** Foundation. The raw value round-trips whatever it is
/// handed, so a document written by a later build reaches the refusal with its
/// name intact rather than being decoded into something else.
public struct SessionIcon: RawRepresentable, Codable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Barbell work — the ordinary strength session.
    public static let strength = SessionIcon(rawValue: "strength")
    /// Dumbbells, kettlebells, machines: strength that is not a barbell.
    public static let accessory = SessionIcon(rawValue: "accessory")
    /// Trunk work.
    public static let core = SessionIcon(rawValue: "core")
    /// Stretching and range of motion.
    public static let mobility = SessionIcon(rawValue: "mobility")
    /// Running.
    public static let run = SessionIcon(rawValue: "run")
    /// Rowing.
    public static let row = SessionIcon(rawValue: "row")
    /// Steps, hills, the stair machine.
    public static let stairs = SessionIcon(rawValue: "stairs")
    /// Intervals — work and rest, hard.
    public static let intervals = SessionIcon(rawValue: "intervals")
    /// Walking, including a loaded carry done as a walk.
    public static let walk = SessionIcon(rawValue: "walk")
    /// Mixed conditioning that is none of the above on its own.
    public static let conditioning = SessionIcon(rawValue: "conditioning")
    /// A bike, indoors or out.
    public static let cycle = SessionIcon(rawValue: "cycle")
    /// The elliptical.
    public static let elliptical = SessionIcon(rawValue: "elliptical")
    /// Swimming.
    public static let swim = SessionIcon(rawValue: "swim")
    /// Walking uphill, on a trail or loaded.
    public static let hike = SessionIcon(rawValue: "hike")
    /// Climbing, on a wall or a board.
    public static let climb = SessionIcon(rawValue: "climb")
    /// Skipping — the rope, as its own session or as the warm-up that is one.
    public static let jumpRope = SessionIcon(rawValue: "jumprope")
    /// Bag work, pads, sparring. **Named for the modality and not the sport**,
    /// so one mark covers boxing, kickboxing and everything beside them —
    /// `boxing` would invite `muaythai` and `bjj`, and the set is closed.
    public static let combat = SessionIcon(rawValue: "combat")
    /// Bodyweight skill work — handstands, rings, levers.
    public static let gymnastics = SessionIcon(rawValue: "gymnastics")

    /// Every mark this build can draw, in the order the tool schema lists them.
    ///
    /// The schema is built from this array rather than retyping the names, so a
    /// mark added here is offered to the coach in the same commit and one
    /// removed stops being offered.
    /// **They are named for the modality, never for the sport.** *Row* covers
    /// the erg and the water; *combat* covers boxing, kickboxing and the rest.
    /// A sport name reads better on one session and invites the next one the set
    /// does not have — and the coach is refused for a mark this build cannot
    /// draw, so every name he might reasonably reach for has to already be here.
    ///
    /// **A mark earns its place by being a session somebody prescribes and a
    /// glyph the eye can tell from the others.** Equipment is not an axis: a
    /// treadmill run and an outdoor run are one modality on two machines, so
    /// there is one `run`.
    public static let all: [SessionIcon] = [
        .strength, .accessory, .core, .gymnastics, .mobility,
        .run, .walk, .hike, .row, .cycle, .elliptical, .stairs,
        .swim, .climb, .jumpRope, .combat, .intervals, .conditioning,
    ]

    /// Whether this build can draw it. `PlanImporter` asks before storing.
    public var isKnown: Bool { Self.all.contains(self) }
}
