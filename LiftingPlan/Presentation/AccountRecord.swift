import Foundation
import LiftingKit

/// One fact the record holds about the lifter, ready to draw as a row.
///
/// **What it does.** Carries the two strings a row prints and the glyph beside
/// them. `value` is the fact — his words, his weight, his days — and `label`
/// names it. The label leads on screen: six values of different lengths with no
/// shared left edge gave the page no column to scan, and a fact about the lifter
/// should read the same way as a fact about a movement, which
/// `ExerciseAboutSections` already draws label-first. A weigh-in's date rides on
/// the label for the same
/// reason, as something that qualifies the number rather than something to give
/// a row of its own.
///
/// **How it is used.** `AccountRecord` builds them and `AccountView` draws each
/// through `FactRow`. A row exists only for a fact somebody has stated —
/// there is no row that means "empty", because a page of them would say nothing
/// at length.
///
/// **What it depends on.** Foundation, and nothing else. It holds no model and
/// no id of one: everything on it has already been resolved to text.
struct LifterFactRow: Identifiable, Equatable {

    /// The fact, in the words or the units it was stated in.
    let value: String

    /// What the fact is called, and anything qualifying it.
    let label: String

    var id: String { label }
}

/// What the record holds about the lifter, and what it does not hold yet.
///
/// **What it does.** Reads the stored profile, the bodyweight series and the
/// strength baselines and answers with the rows the account page prints, plus
/// the names of the facts nobody has stated. Nothing here decides anything
/// about training, converts a weight, or substitutes a value for one that is
/// missing: an unstated fact is reported as unstated and never as a plausible
/// default, because the app asks the lifter nothing and every field here was
/// filled in by Claude or by nobody.
///
/// **How it is used.** `AccountView` calls `facts`, `baselines` and
/// `notYetSaid` and draws the results. It lives apart from the view because a
/// list that must never say "0 lb" for a weight nobody stated is worth testing
/// against strings rather than against a screenshot.
///
/// **What it depends on.** The `Store/` models, and `ExerciseCatalogProviding`
/// from LiftingKit to turn an `ExerciseID` into the name the lifter would use.
/// It writes nothing.
///
/// The eight facts `notYetSaid` surveys are the eight the MCP server's
/// `unstated_facts` surveys, for the same reason and with the same two
/// exclusions: `displayUnit` always has a value and is about how a number is
/// drawn, and the avoided lists have no absent state — an empty one cannot be
/// told from a lifter who avoids nothing, so calling it unsaid would assert
/// something the record does not know.
enum AccountRecord {

    /// Everything stated about the lifter, in reading order: who he is, what he
    /// avoids, what he weighs, what he trains with, and when.
    static func facts(
        profile: UserProfile, weighIns: [BodyMetric], catalog: any ExerciseCatalogProviding
    ) -> [LifterFactRow] {
        [
            row(profile.goal, "Goal"),
            row(profile.experience.map { sentenceCased($0.rawValue) }, "Experience"),
            row(profile.constraints, "Constraints"),
            row(patterns(profile), "Avoided movements"),
            row(exercises(profile, catalog: catalog), "Avoided exercises"),
            bodyweight(profile: profile, weighIns: weighIns),
            row(equipment(profile), "Equipment"),
            row(weekdays(profile), "Training days"),
            row(profile.preferredDurationMinutes.map { "\($0) min" }, "Session length"),
        ].compactMap { $0 }
    }

    /// The lifter's starting points, one per lift, under the name he would call
    /// it rather than under the slug the record is keyed on.
    ///
    /// A baseline with no load is a bodyweight one and says so — the same
    /// distinction `LoggedSet.load` keeps, and the reason it is not written as
    /// a zero.
    static func baselines(
        _ stored: [StrengthBaseline], catalog: any ExerciseCatalogProviding
    ) -> [LifterFactRow] {
        stored
            .map { baseline in
                LifterFactRow(
                    value: "\(load(baseline.load)) × \(baseline.reps)",
                    label: catalog.exercise(id: baseline.exerciseID)?.displayName
                        ?? baseline.exerciseID.rawValue
                )
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// The facts this record can hold that nobody has stated yet, named as the
    /// lifter would say them rather than as `update_profile` spells them.
    ///
    /// They are named, rather than each drawn as an empty row, because most of
    /// them are empty for most of the life of a record: eight rows saying
    /// nothing would be the whole screen on day one. Naming them still answers
    /// the question a blank page cannot — what could Claude know about me? —
    /// at the cost of one sentence.
    static func notYetSaid(
        profile: UserProfile, weighIns: [BodyMetric], baselineCount: Int
    ) -> [String] {
        var unstated: [String] = []
        if profile.goal.isEmpty { unstated.append("goal") }
        if profile.experience == nil { unstated.append("experience") }
        if profile.constraints.isEmpty { unstated.append("constraints") }
        if latestWeight(profile: profile, weighIns: weighIns) == nil {
            unstated.append("bodyweight")
        }
        if profile.ownedEquipment == nil { unstated.append("equipment") }
        if profile.preferredWeekdays.isEmpty { unstated.append("training days") }
        if profile.preferredDurationMinutes == nil { unstated.append("session length") }
        if baselineCount == 0 { unstated.append("strength baselines") }
        return unstated
    }

    /// The names as one sentence — `"Goal, bodyweight and equipment."` — or
    /// `nil` when the record holds everything it can.
    static func sentence(_ names: [String]) -> String? {
        guard let last = names.last else { return nil }
        let joined = names.count == 1
            ? last
            : names.dropLast().joined(separator: ", ") + " and " + last
        // Not sentence-cased. It used to lead its own line and now follows
        // "Not yet said:", where a capital mid-sentence reads as a mistake
        // rather than as a list.
        return joined + "."
    }

    // MARK: - The facts, one at a time

    /// Bodyweight as the record holds it: the latest reading, and the day it
    /// was taken when the series says which day that was.
    ///
    /// Deliberately one line rather than a trend. The series exists and a chart
    /// could be drawn from it; nobody asked for one, and a number with a date
    /// on it answers "what do I weigh" — which is the question an account page
    /// is being read for.
    private static func bodyweight(
        profile: UserProfile, weighIns: [BodyMetric]
    ) -> LifterFactRow? {
        guard let mass = latestWeight(profile: profile, weighIns: weighIns) else { return nil }
        let taken = latestReading(weighIns).map {
            " · \($0.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return LifterFactRow(
            value: text(mass), label: "Bodyweight\(taken ?? "")")
    }

    /// The weight the record stands behind: the last dated reading, or the copy
    /// on the profile when nothing dated it. The same order the MCP server
    /// reads them in, so the two cannot report different weights.
    private static func latestWeight(profile: UserProfile, weighIns: [BodyMetric]) -> Mass? {
        latestReading(weighIns)?.bodyweight ?? profile.bodyweight
    }

    /// The most recent reading that actually holds a weight. A `BodyMetric`
    /// with none is a day nothing was recorded on, not the current answer.
    private static func latestReading(_ weighIns: [BodyMetric]) -> BodyMetric? {
        weighIns.filter { $0.bodyweight != nil }.max { $0.date < $1.date }
    }

    /// What he owns, alphabetically. An empty list is a lifter who owns
    /// nothing, which is a statement — `nil` is a lifter nobody has asked, and
    /// only that one goes unshown.
    private static func equipment(_ profile: UserProfile) -> String? {
        guard let owned = profile.ownedEquipment else { return nil }
        guard !owned.isEmpty else { return "No equipment" }
        return list(owned.map(\.rawValue))
    }

    private static func patterns(_ profile: UserProfile) -> String? {
        list(profile.avoidedPatterns.map(\.rawValue))
    }

    private static func exercises(
        _ profile: UserProfile, catalog: any ExerciseCatalogProviding
    ) -> String? {
        list(profile.avoidedExercises.map {
            catalog.exercise(id: $0)?.displayName ?? $0.rawValue
        })
    }

    private static func weekdays(_ profile: UserProfile) -> String? {
        let days = profile.orderedPreferredWeekdays.map(\.shortName)
        return days.isEmpty ? nil : days.joined(separator: ", ")
    }

    private static func load(_ mass: Mass?) -> String {
        mass.map(text) ?? "Bodyweight"
    }

    /// A weight as it was entered, in the unit it was entered in. Never
    /// converted to the display unit: `Mass` does not canonicalize, and a
    /// baseline he stated as 205 lb is not something the record restates.
    private static func text(_ mass: Mass) -> String {
        "\(mass.value.compactString) \(mass.unit.rawValue)"
    }

    // MARK: - Words

    private static func row(_ value: String?, _ label: String) -> LifterFactRow? {
        guard let value, !value.isEmpty else { return nil }
        return LifterFactRow(value: value, label: label)
    }

    /// Taxonomy values sorted and joined, or `nil` when there are none. Sorted
    /// because a set has no order of its own and the same record must read the
    /// same way twice.
    private static func list(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        return values.sorted().map(sentenceCased).joined(separator: ", ")
    }

    /// The first letter raised, and nothing else touched. Not `capitalized`:
    /// experience is whatever the lifter said about himself, and "Coming Back
    /// After Two Years Off" is not what he said.
    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
