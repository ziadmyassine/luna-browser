//
//  FolderEmoji.swift
//  Luna
//
//  §3.4b: an emoji for a folder, read from its name. "Running shoes" gets 👟,
//  "Gaming" 🎮, "Skole" 🏫. A folder named and never given an icon gets one
//  that says what it holds, and one the user chose is never touched (see
//  `BrowserSession.renameGroup`).
//
//  Two sources, in order. A short list of the things people make folders
//  for, in English and Danish, because the emoji a person expects for "work"
//  (💼) is not one whose Unicode name says WORK. Then every emoji's own
//  Unicode name, so "rocket" or "volcano" still find theirs. A name with no
//  word either knows keeps the folder symbol: a wrong guess is worse than none.
//

import Foundation
import NaturalLanguage

enum FolderEmoji {

    /// The emoji for a folder called `name`, or nil when nothing in it says
    /// clearly enough what the folder is for.
    ///
    /// An emoji typed into the name is taken as it is. Otherwise the words are
    /// read from the last: in "running shoes" the thing is the shoes, and in
    /// English the noun a name is about comes at its end.
    static func suggestion(for name: String) -> String? {
        if let typed = name.first(where: isEmoji) { return String(typed) }
        let words = Self.words(in: name)
        for word in words.reversed() {
            for form in forms(of: word) {
                if let emoji = topics[form] { return emoji }
            }
        }
        for word in words.reversed() {
            for form in forms(of: word) where form.count >= 4 {
                if let emoji = unicodeNames[form] { return emoji }
            }
        }
        return nil
    }

    private static func isEmoji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && character.unicodeScalars.count > 1)
    }

    /// Lower-cased words, without the ones that say nothing about a topic.
    private static func words(in name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// The word, its dictionary form, and the plain endings taken off —
    /// "shoes" is filed as "shoe", "running" as "run", "gaming" as "game".
    private static func forms(of word: String) -> [String] {
        var forms = [word]
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        if let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased() {
            forms.append(lemma)
        }
        for (ending, replacement) in [("ies", "y"), ("es", ""), ("s", ""), ("ing", ""), ("ing", "e"), ("er", ""), ("ers", "")]
            where word.hasSuffix(ending) && word.count > ending.count + 2 {
            forms.append(String(word.dropLast(ending.count)) + replacement)
        }
        // "running" → "runn" → "run": a doubled consonant before -ing.
        for form in forms where form.count > 3 && form.last == form.dropLast().last {
            forms.append(String(form.dropLast()))
        }
        var seen = Set<String>()
        return forms.filter { seen.insert($0).inserted }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "my", "our", "your", "his", "her", "their", "and", "or", "of", "for", "to", "in",
        "on", "at", "by", "with", "from", "is", "are", "be", "it", "this", "that", "what", "up", "new", "old",
        "misc", "stuff", "things", "other", "folder", "folders", "tab", "tabs", "link", "links", "list", "page",
        "pages", "site", "sites", "untitled", "og", "de", "den", "det", "en", "et", "til", "med", "min", "mit",
        "mine", "ny", "nye", "andet", "ting"
    ]

    /// What people make folders for, and the emoji they expect for it.
    private static let topics: [String: String] = {
        var table: [String: String] = [:]
        for (emoji, words) in topicList {
            for word in words where table[word] == nil { table[word] = emoji }
        }
        return table
    }()

    private static let topicList: [(String, [String])] = [
        ("💼", ["work", "job", "office", "career", "business", "arbejde", "kontor"]),
        ("📅", ["meeting", "meetings", "calendar", "schedule", "event", "events", "møde", "kalender"]),
        ("🏫", ["school", "class", "skole", "gymnasium"]),
        ("🎓", ["university", "uni", "college", "graduation", "degree", "studie", "universitet"]),
        ("📚", ["study", "studies", "book", "library", "course", "lecture", "bog", "bøger", "lektier"]),
        ("📝", ["homework", "notes", "note", "assignment", "essay", "exam", "noter", "opgave", "eksamen"]),
        ("🧮", ["math", "maths", "mathematics", "matematik"]),
        ("🔬", ["science", "research", "lab", "physics", "fysik", "videnskab"]),
        ("🧪", ["chemistry", "kemi", "experiment"]),
        ("🧬", ["biology", "biologi", "genetics"]),
        ("📜", ["history", "historie"]),
        ("🗣️", ["language", "languages", "sprog", "english", "danish", "spanish", "french", "german"]),
        ("💻", ["code", "coding", "programming", "developer", "dev", "software", "computer", "mac", "laptop", "kode"]),
        ("🖥️", ["pc", "desktop", "monitor", "setup"]),
        ("⌨️", ["keyboard", "tastatur"]),
        ("🎨", ["design", "art", "drawing", "painting", "illustration", "kunst", "tegning"]),
        ("📷", ["photo", "photos", "photography", "camera", "picture", "pictures", "billeder", "foto", "kamera"]),
        ("🎬", ["video", "film", "movie", "movies", "cinema", "editing"]),
        ("📺", ["tv", "series", "show", "shows", "netflix", "streaming", "serier"]),
        ("🎵", ["music", "song", "songs", "playlist", "spotify", "musik", "sang"]),
        ("🎸", ["guitar", "band", "guitarr"]),
        ("🎹", ["piano", "klaver"]),
        ("🎙️", ["podcast", "podcasts", "radio"]),
        ("📰", ["news", "newspaper", "nyheder", "avis"]),
        ("📖", ["reading", "read", "article", "articles", "blog", "læsning"]),
        ("🎮", ["game", "games", "gaming", "gamer", "playstation", "xbox", "nintendo", "steam", "spil"]),
        ("♟️", ["chess", "skak"]),
        ("⚽", ["football", "soccer", "sport", "sports", "fodbold"]),
        ("🏀", ["basketball", "nba"]),
        ("🎾", ["tennis", "padel"]),
        ("⛳", ["golf"]),
        ("🏎️", ["f1", "formula", "racing", "motorsport"]),
        ("🏃", ["run", "running", "runner", "marathon", "jogging", "løb", "løbe"]),
        ("🏋️", ["gym", "fitness", "workout", "training", "exercise", "træning", "styrketræning"]),
        ("🧘", ["yoga", "meditation", "mindfulness"]),
        ("🚲", ["bike", "bicycle", "cycling", "cykel", "cykling"]),
        ("🏊", ["swim", "swimming", "svømning"]),
        ("🥾", ["hike", "hiking", "outdoor", "camping", "vandring"]),
        ("👟", ["shoe", "shoes", "sneaker", "sneakers", "sko"]),
        ("👕", ["clothes", "clothing", "shirt", "outfit", "tøj"]),
        ("👗", ["fashion", "dress", "style"]),
        ("🛍️", ["shop", "shopping", "store", "buy", "wishlist", "butik"]),
        ("🛒", ["groceries", "grocery", "cart", "indkøb", "dagligvarer"]),
        ("🎁", ["gift", "gifts", "present", "presents", "gave", "gaver"]),
        ("🎄", ["christmas", "xmas", "jul"]),
        ("🎂", ["birthday", "fødselsdag"]),
        ("🎉", ["party", "celebration", "fest"]),
        ("💍", ["wedding", "engagement", "bryllup"]),
        ("✈️", ["travel", "trip", "trips", "flight", "flights", "rejse", "rejser", "fly"]),
        ("🏖️", ["holiday", "vacation", "beach", "summer", "ferie", "sommer", "strand"]),
        ("🏨", ["hotel", "hotels", "airbnb", "booking"]),
        ("🗺️", ["map", "maps", "kort"]),
        ("🚗", ["car", "cars", "auto", "driving", "bil", "biler"]),
        ("🏠", ["home", "house", "apartment", "flat", "rent", "housing", "hjem", "hus", "lejlighed", "bolig"]),
        ("🛋️", ["furniture", "interior", "decor", "møbler", "indretning"]),
        ("🌱", ["garden", "gardening", "plant", "plants", "planter"]),
        ("🍔", ["food", "eat", "eating", "mad"]),
        ("🍳", ["recipe", "recipes", "cooking", "cook", "baking", "opskrift", "opskrifter", "madlavning"]),
        ("🍽️", ["restaurant", "restaurants", "dinner", "lunch", "middag"]),
        ("☕", ["coffee", "cafe", "kaffe"]),
        ("🍷", ["wine", "vin"]),
        ("🍺", ["beer", "øl", "bar"]),
        ("🍕", ["pizza"]),
        ("🩺", ["health", "doctor", "medical", "hospital", "sundhed", "læge"]),
        ("💊", ["medicine", "pharmacy", "medicin", "apotek"]),
        ("🧠", ["learn", "learning", "brain", "psychology", "mental", "psykologi"]),
        ("😴", ["sleep", "søvn"]),
        ("💄", ["beauty", "makeup", "skincare", "skønhed"]),
        ("💰", ["money", "finance", "finances", "economy", "savings", "penge", "økonomi", "opsparing"]),
        ("🏦", ["bank", "banking", "loan", "mortgage", "lån"]),
        ("📈", ["invest", "investing", "investment", "investments", "stock", "stocks", "trading", "aktier"]),
        ("🪙", ["crypto", "bitcoin", "ethereum"]),
        ("🧾", ["tax", "taxes", "bill", "bills", "invoice", "invoices", "receipt", "receipts", "skat", "regning", "faktura"]),
        ("🛡️", ["insurance", "forsikring"]),
        ("🚀", ["startup", "launch", "rocket", "space"]),
        ("💡", ["idea", "ideas", "inspiration", "ideer", "idéer"]),
        ("✅", ["todo", "todos", "task", "tasks", "checklist", "opgaver"]),
        ("📌", ["later", "pinned", "bookmark", "bookmarks", "saved", "senere"]),
        ("🔍", ["search", "find", "søg"]),
        ("🤖", ["ai", "chatgpt", "claude", "robot", "robots", "ml"]),
        ("📱", ["app", "apps", "phone", "iphone", "ios", "android", "mobile", "telefon"]),
        ("🛠️", ["tool", "tools", "repair", "diy", "fix", "værktøj"]),
        ("⚙️", ["settings", "config", "admin", "indstillinger"]),
        ("🔒", ["private", "security", "secret", "privat", "sikkerhed"]),
        ("🔑", ["password", "passwords", "login", "account", "accounts", "konto"]),
        ("📧", ["email", "mail", "inbox", "newsletter"]),
        ("💬", ["chat", "messages", "message", "beskeder"]),
        ("👥", ["social", "friends", "team", "people", "community", "venner"]),
        ("👨‍👩‍👧", ["family", "familie"]),
        ("👶", ["baby", "kids", "children", "børn"]),
        ("🐶", ["dog", "dogs", "puppy", "hund"]),
        ("🐱", ["cat", "cats", "kitten", "kat"]),
        ("🐾", ["pet", "pets", "animal", "animals", "dyr"]),
        ("🌿", ["nature", "natur"]),
        ("🌍", ["climate", "earth", "world", "environment", "klima", "verden"]),
        ("☀️", ["weather", "vejr"]),
        ("⚡", ["energy", "electric", "power", "energi"]),
        ("🏛️", ["politics", "government", "politik"]),
        ("⚖️", ["law", "legal", "lawyer", "jura", "advokat"]),
        ("📄", ["doc", "docs", "document", "documents", "pdf", "cv", "resume", "dokumenter"]),
        ("📣", ["marketing", "ads", "advertising", "campaign"]),
        ("🤝", ["client", "clients", "customer", "customers", "sales", "kunder", "salg"]),
        ("✍️", ["writing", "write", "author", "skrivning"]),
        ("🎟️", ["ticket", "tickets", "concert", "concerts", "festival", "billetter", "koncert"]),
        ("❤️", ["love", "dating", "favorite", "favorites", "favourites", "kærlighed", "favoritter"]),
        ("⭐", ["important", "star", "starred", "vigtigt"]),
        ("🗄️", ["archive", "archived", "arkiv"]),
        ("🎌", ["anime", "manga"]),
        ("🇩🇰", ["denmark", "danmark", "copenhagen", "københavn"]),
        ("🍎", ["apple"]),
        ("🖨️", ["print", "printing", "3d"]),
        ("⛪", ["church", "religion", "faith", "bible", "kirke"])
    ]

    /// Every emoji, filed under each word of its Unicode name: 🚀 under
    /// "rocket", 🌋 under "volcano". Built once, the first time a folder is
    /// named and the short list above did not know the word.
    private static let unicodeNames: [String: String] = {
        var table: [String: String] = [:]
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF,
                                             0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x2600...0x27BF]
        let vague: Set<String> = ["sign", "symbol", "with", "face", "hand", "black", "white", "large", "small",
                                  "medium", "button", "mark", "heavy", "light", "type", "squared", "circled"]
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                      let name = scalar.properties.name?.lowercased()
                else { continue }
                for word in name.split(separator: " ").map(String.init)
                    where word.count >= 4 && !vague.contains(word) && table[word] == nil {
                    table[word] = String(scalar)
                }
            }
        }
        return table
    }()
}
