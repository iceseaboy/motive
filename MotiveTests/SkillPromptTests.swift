import Testing
@testable import Motive

@MainActor
struct SkillPromptTests {
    @Test func availableSkillsListAppearsWhenNotEmpty() async throws {
        let skills = [
            SkillEntry(
                name: "slack",
                description: "Slack skill",
                filePath: "/tmp/slack/SKILL.md",
                source: .managed,
                frontmatter: SkillFrontmatter(name: "slack", description: "Slack skill"),
                metadata: nil,
                invocation: SkillInvocationPolicy(),
                wiring: .none,
                eligibility: SkillEligibility(isEligible: true, reasons: [])
            )
        ]

        let output = await SystemPromptBuilder.formatAvailableSkills(skills)
        #expect(output.contains("<available_skills>"))
        #expect(output.contains("<name>slack</name>"))
        #expect(output.contains("/tmp/slack/SKILL.md"))
    }

    @Test func availableSkillsListIsEmptyWhenNoSkills() async throws {
        let output = await SystemPromptBuilder.formatAvailableSkills([])
        #expect(output.isEmpty)
    }
}
