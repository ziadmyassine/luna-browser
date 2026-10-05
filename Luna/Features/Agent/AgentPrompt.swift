//
//  AgentPrompt.swift
//  Luna
//
//  Whether what was typed into ⌘T reads as a task for the agent rather than
//  a search: the Command Bar offers "Ask your agent" only then. A few words
//  are a search; a sentence, or a short one that starts the way a request
//  starts, is a task.
//

import Foundation

enum AgentPrompt {

    /// Words a request opens with — what to do, or a question — in English
    /// and Danish.
    private static let openers: Set<String> = [
        "find", "book", "compare", "summarize", "summarise", "catch", "show", "get", "buy", "order", "plan",
        "research", "check", "look", "tell", "help", "write", "draft", "fill", "sign", "go", "list", "track",
        "cancel", "reply", "send", "read", "collect", "organize", "organise", "make", "create", "add",
        "remove", "explain", "translate", "what", "how", "why", "when", "where", "which", "who", "can",
        "could", "would", "please", "i", "i'm", "i'd", "is", "are", "do", "does",
        "sammenlign", "hvad", "hvordan", "hvorfor", "hvornår", "hvor", "kan", "vil", "jeg", "skriv", "læs"
    ]

    /// Words that put the user in the sentence, which a search rarely does.
    private static let personal: Set<String> = ["me", "my", "mine", "please", "mig", "min", "mine", "mit"]

    static func reads(_ query: String) -> Bool {
        let words = query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard words.count >= 3 else { return false }
        if words.count >= 5 || query.contains("?") { return true }
        return openers.contains(words[0]) || words.contains(where: personal.contains)
    }
}
