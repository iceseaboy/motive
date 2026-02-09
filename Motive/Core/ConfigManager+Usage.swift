//
//  ConfigManager+Usage.swift
//  Motive
//
//  Token usage tracking and persistence.
//

import Foundation

extension ConfigManager {
    struct TokenUsageTotals: Codable, Sendable, Equatable {
        var input: Int
        var output: Int
        var reasoning: Int
        var cacheRead: Int
        var cacheWrite: Int
        var cost: Double

        var totalTokens: Int {
            input + output + reasoning + cacheRead + cacheWrite
        }
    }

    struct TokenUsageEntry: Identifiable, Sendable, Equatable {
        let id: String
        let model: String
        let totals: TokenUsageTotals

        var displayName: String {
            if let slashIndex = model.lastIndex(of: "/") {
                return String(model[model.index(after: slashIndex)...])
            }
            return model
        }
    }

    func recordTokenUsage(model: String, usage: TokenUsage, cost: Double?) {
        var usageMap = loadTokenUsageTotals()
        let normalizedModel = normalizeModelKey(model)
        let existing = usageMap[normalizedModel] ?? TokenUsageTotals(
            input: 0,
            output: 0,
            reasoning: 0,
            cacheRead: 0,
            cacheWrite: 0,
            cost: 0
        )
        let updated = TokenUsageTotals(
            input: existing.input + usage.input,
            output: existing.output + usage.output,
            reasoning: existing.reasoning + usage.reasoning,
            cacheRead: existing.cacheRead + usage.cacheRead,
            cacheWrite: existing.cacheWrite + usage.cacheWrite,
            cost: existing.cost + (cost ?? 0)
        )
        usageMap[normalizedModel] = updated
        saveTokenUsageTotals(usageMap)
    }

    func resetTokenUsage() {
        saveTokenUsageTotals([:])
    }

    func tokenUsageEntries() -> [TokenUsageEntry] {
        let map = loadTokenUsageTotals()
        return map.map { key, totals in
            TokenUsageEntry(id: key, model: key, totals: totals)
        }
        .sorted { lhs, rhs in
            if lhs.totals.totalTokens == rhs.totals.totalTokens {
                return lhs.model < rhs.model
            }
            return lhs.totals.totalTokens > rhs.totals.totalTokens
        }
    }

    private func loadTokenUsageTotals() -> [String: TokenUsageTotals] {
        guard let data = tokenUsageTotalsJSON.data(using: .utf8) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: TokenUsageTotals].self, from: data)) ?? [:]
    }

    private func saveTokenUsageTotals(_ totals: [String: TokenUsageTotals]) {
        if let data = try? JSONEncoder().encode(totals),
           let json = String(data: data, encoding: .utf8) {
            tokenUsageTotalsJSON = json
        } else {
            tokenUsageTotalsJSON = "{}"
        }
    }

    /// Normalize model key: just trim whitespace.
    /// The model name comes directly from OpenCode's modelID field (e.g. "gemini-3-flash-preview").
    private func normalizeModelKey(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
