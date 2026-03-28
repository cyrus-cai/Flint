import Foundation

struct FlintSkill: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// The SKILL.md body — what gets written into the skill file.
    let skillBody: String

    /// The full text copied to the clipboard: an instruction for Claude Code + the skill content.
    var clipboardText: String {
        """
        Please create a new Claude Code skill named "\(id)" with the following content:

        \(skillBody)
        """
    }
}

extension FlintSkill {
    static let builtIn: [FlintSkill] = [dailyDigest, weeklyReview]

    /// Single clipboard text that asks Claude Code to create all built-in skills at once.
    static var allSkillsClipboardText: String {
        let skillSections = builtIn.map { skill in
            """
            ## Skill: \(skill.id)

            \(skill.skillBody)
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        Please create the following Claude Code skills for Flint:

        \(skillSections)
        """
    }

    static let dailyDigest = FlintSkill(
        id: "flint-daily-digest",
        title: "Daily Digest",
        subtitle: "Summarize yesterday's notes",
        skillBody: """
        ---
        name: flint-daily-digest
        description: Summarize yesterday's Flint notes into a structured digest
        ---

        # flint-daily-digest

        ## Instructions
        1. Use the `list_notes` tool to list notes from the current ISO week (e.g. "2026W13"). If yesterday was in the previous week, also list that week's notes.
        2. Filter for notes whose `modified` date is yesterday.
        3. Use `read_note` to read the full content of each note from yesterday.
        4. Generate a digest with these sections:
           - **Key Notes** — the most important items, one sentence each
           - **Ideas & Inspirations** — any creative thoughts or future plans
           - **Action Items** — anything that looks like a TODO or follow-up
        5. Create a new Flint note with `create_note` titled "Daily Digest — <YYYY-MM-DD>", containing the structured digest.
        6. If there were no notes yesterday, create a brief note saying "No notes captured yesterday."
        """
    )

    static let weeklyReview = FlintSkill(
        id: "flint-weekly-review",
        title: "Weekly Review",
        subtitle: "Review and organize this week's notes",
        skillBody: """
        ---
        name: flint-weekly-review
        description: Review and organize the current week's Flint notes into a structured weekly summary
        ---

        # flint-weekly-review

        ## Instructions
        1. Use `get_status` to confirm the current ISO week.
        2. Use `list_notes` with the current week filter to get all notes this week.
        3. Use `read_note` to read each note's full content.
        4. Generate a weekly review with these sections:
           - **Overview** — a 2-3 sentence summary of what the week was about
           - **Key Themes** — group related notes by topic, list each theme with its note count
           - **Highlights** — the most valuable or interesting notes (up to 5)
           - **Open Items** — unresolved TODOs, questions, or ideas that need follow-up
           - **Stats** — total notes, busiest day, avg notes per day
        5. Create a new Flint note with `create_note` titled "Weekly Review — <YYYY> Week <N>", containing the review.
        """
    )
}
