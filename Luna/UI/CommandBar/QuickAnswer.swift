//
//  QuickAnswer.swift
//  Luna
//
//  §9.2's maths and unit answers: a sum or a conversion typed into the bar is
//  answered on its top row, and Return copies the answer.
//
//  Offline by construction — Foundation's `Measurement` and a small parser,
//  nothing else — so no currency: a rate is a network answer, and nothing
//  under `Luna/UI/CommandBar` asks the network (§9.6). Synchronous and pure,
//  because it runs inside §9.7's keystroke; a query that does not start like a
//  number is turned away on its first character.
//

import Foundation

struct QuickAnswer: Sendable, Hashable {

    /// What the row shows and Return copies: `42`, `3.10686 mi`.
    let value: String
    /// The question as it was read, for the row's second line.
    let question: String
    let isConversion: Bool

    static func answer(for rawQuery: String) -> QuickAnswer? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = query.first, first.isNumber || "(-−.,".contains(first) else { return nil }
        return Conversion.answer(for: query) ?? Arithmetic.answer(for: query)
    }

    /// Twelve significant digits for a sum, so `0.1 + 0.2` is `0.3`, and six
    /// for a conversion, whose inputs are rarely that exact. A comma where the
    /// question used one.
    static func format(_ value: Double, digits: Int, decimalComma: Bool) -> String {
        let magnitude = abs(value)
        var text: String
        if magnitude != 0, magnitude >= 1e15 || magnitude < 1e-9 {
            text = String(format: "%.\(digits)g", value)
        } else {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = digits
            text = formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? "\(value)"
        }
        return decimalComma ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// A number at the front of `text`: digits with at most one `.` or `,`
    /// as the decimal mark. Returns it, whether the mark was a comma, and
    /// what follows.
    static func leadingNumber(_ text: Substring) -> (value: Double, comma: Bool, rest: Substring)? {
        var end = text.startIndex
        var mark: Character?
        while end < text.endIndex {
            let character = text[end]
            if character.isASCII, character.isNumber {
                end = text.index(after: end)
            } else if character == "." || character == ",", mark == nil {
                mark = character
                end = text.index(after: end)
            } else {
                break
            }
        }
        let digits = text[text.startIndex..<end].replacingOccurrences(of: ",", with: ".")
        guard digits.contains(where: \.isNumber), let value = Double(digits) else { return nil }
        return (value, mark == ",", text[end...])
    }
}

// MARK: - Sums

/// `+ - × ÷ * / ^ %` and parentheses, by recursive descent. `%` after a
/// number is per cent (`15%` is 0.15, `200 * 15%` is 30); between two numbers
/// it is the remainder, as a calculator's `mod` key is.
private struct Arithmetic {

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close
    }

    private let tokens: [Token]
    private var position = 0
    /// Whether anything other than a lone number was read: `42` is not a sum.
    private var operated = false

    static func answer(for query: String) -> QuickAnswer? {
        guard let (tokens, comma) = tokenize(query) else { return nil }
        var parser = Arithmetic(tokens: tokens)
        guard let value = parser.expression(), parser.position == tokens.count, parser.operated, value.isFinite
        else { return nil }
        return QuickAnswer(
            value: QuickAnswer.format(value, digits: 12, decimalComma: comma),
            question: query,
            isConversion: false
        )
    }

    private init(tokens: [Token]) {
        self.tokens = tokens
    }

    private static func tokenize(_ text: String) -> ([Token], comma: Bool)? {
        let operators: [Character: Character] = [
            "+": "+", "-": "-", "−": "-", "*": "*", "×": "*", "·": "*", "/": "/", "÷": "/", "^": "^", "%": "%"
        ]
        var tokens: [Token] = []
        var comma = false
        var rest = Substring(text)
        while let character = rest.first {
            if character.isWhitespace {
                rest = rest.dropFirst()
            } else if let op = operators[character] {
                tokens.append(.op(op))
                rest = rest.dropFirst()
            } else if character == "(" || character == ")" {
                tokens.append(character == "(" ? .open : .close)
                rest = rest.dropFirst()
            } else if let number = QuickAnswer.leadingNumber(rest) {
                tokens.append(.number(number.value))
                comma = comma || number.comma
                rest = number.rest
            } else {
                return nil
            }
        }
        return (tokens, comma)
    }

    private var next: Token? { position < tokens.count ? tokens[position] : nil }

    /// Whether the token after the current one starts an operand.
    private var operandFollows: Bool {
        guard position + 1 < tokens.count else { return false }
        switch tokens[position + 1] {
        case .number, .open, .op("-"), .op("+"): return true
        default: return false
        }
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while case .op(let op)? = next, op == "+" || op == "-" {
            position += 1
            operated = true
            guard let right = term() else { return nil }
            value = op == "+" ? value + right : value - right
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = unary() else { return nil }
        while case .op(let op)? = next, op == "*" || op == "/" || (op == "%" && operandFollows) {
            position += 1
            operated = true
            guard let right = unary() else { return nil }
            switch op {
            case "*": value *= right
            case "/":
                guard right != 0 else { return nil }
                value /= right
            default:
                guard right != 0 else { return nil }
                value = value.truncatingRemainder(dividingBy: right)
            }
        }
        return value
    }

    /// Looser than `^`, so `-2^2` is −4, as written on paper.
    private mutating func unary() -> Double? {
        if case .op(let op)? = next, op == "-" || op == "+" {
            position += 1
            return unary().map { op == "-" ? -$0 : $0 }
        }
        return power()
    }

    /// Right-associative: `2^3^2` is 2⁹.
    private mutating func power() -> Double? {
        guard let base = percent() else { return nil }
        guard case .op("^")? = next else { return base }
        position += 1
        operated = true
        guard let exponent = unary() else { return nil }
        return pow(base, exponent)
    }

    private mutating func percent() -> Double? {
        guard var value = primary() else { return nil }
        while case .op("%")? = next, !operandFollows {
            position += 1
            operated = true
            value /= 100
        }
        return value
    }

    private mutating func primary() -> Double? {
        switch next {
        case .number(let value)?:
            position += 1
            return value
        case .open?:
            position += 1
            guard let value = expression(), next == .close else { return nil }
            position += 1
            return value
        default:
            return nil
        }
    }
}

// MARK: - Conversions

/// `5 km in miles`, `70 f to c`, `2 gb in mb`: a number, a unit, `in`, `to`
/// or `as`, and a unit of the same kind.
private enum Conversion {

    static func answer(for query: String) -> QuickAnswer? {
        let lowered = query.lowercased()
        let negative = lowered.hasPrefix("-") || lowered.hasPrefix("−")
        guard let number = QuickAnswer.leadingNumber(negative ? lowered.dropFirst() : Substring(lowered)) else { return nil }
        let words = number.rest.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let link = words.indices.first(where: { $0 > 0 && ["in", "to", "as", "=", "->", "→"].contains(words[$0]) }),
              link < words.count - 1,
              let (from, kind) = unit(words[..<link].joined(separator: " ")),
              let (into, intoKind) = unit(words[(link + 1)...].joined(separator: " ")),
              kind == intoKind
        else { return nil }
        let value = negative ? -number.value : number.value
        let converted = Measurement(value: value, unit: from).converted(to: into).value
        guard converted.isFinite else { return nil }
        let amount = QuickAnswer.format(value, digits: 12, decimalComma: number.comma)
        return QuickAnswer(
            value: "\(QuickAnswer.format(converted, digits: 6, decimalComma: number.comma)) \(into.symbol)",
            question: "\(amount) \(from.symbol) in \(into.symbol)",
            isConversion: true
        )
    }

    /// `°`, `degrees` and a trailing full stop are ignored, so `70 °F` and
    /// `70 degrees f` read as `70 f`.
    private static func unit(_ name: String) -> (Dimension, Kind)? {
        var key = name.replacingOccurrences(of: "°", with: "")
        if key.hasPrefix("degrees ") { key.removeFirst("degrees ".count) }
        if key.hasSuffix(".") { key.removeLast() }
        return units[key.trimmingCharacters(in: .whitespaces)]
    }

    /// Which units convert into which. Not the `Dimension` subclass:
    /// Foundation's own units are private subclasses of it, so two lengths
    /// need not share a class.
    private enum Kind { case length, mass, temperature, volume, speed, data, time }

    /// Exact where Foundation rounds: its pound is 0.453592 kg and its
    /// kilometre an hour 0.277778 m/s, which shows in the sixth digit.
    private static func exact<U: Dimension>(_ symbol: String, _ coefficient: Double) -> U {
        U(symbol: symbol, converter: UnitConverterLinear(coefficient: coefficient))
    }

    private static let units: [String: (Dimension, Kind)] = {
        var table: [String: (Dimension, Kind)] = [:]
        var kind = Kind.length
        func add(_ unit: Dimension, _ names: String...) { for name in names { table[name] = (unit, kind) } }
        // Length
        add(UnitLength.millimeters, "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add(UnitLength.centimeters, "cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add(UnitLength.meters, "m", "meter", "meters", "metre", "metres")
        add(UnitLength.kilometers, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(UnitLength.inches, "in", "inch", "inches", "\"")
        add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard", "yards")
        add(exact("mi", 1_609.344) as UnitLength, "mi", "mile", "miles")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile", "nautical miles")
        kind = .mass
        add(UnitMass.milligrams, "mg", "milligram", "milligrams")
        add(UnitMass.grams, "g", "gram", "grams", "gramme", "grammes")
        add(UnitMass.kilograms, "kg", "kilo", "kilos", "kilogram", "kilograms")
        add(UnitMass.metricTons, "t", "tonne", "tonnes")
        add(exact("lb", 0.453_592_37) as UnitMass, "lb", "lbs", "pound", "pounds")
        add(exact("oz", 0.028_349_523_125) as UnitMass, "oz", "ounce", "ounces")
        add(exact("st", 6.350_293_18) as UnitMass, "st", "stone", "stones")
        kind = .temperature
        add(UnitTemperature.celsius, "c", "celsius", "centigrade")
        add(UnitTemperature.fahrenheit, "f", "fahrenheit")
        add(UnitTemperature.kelvin, "k", "kelvin")
        kind = .volume
        add(UnitVolume.milliliters, "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add(UnitVolume.centiliters, "cl", "centiliter", "centiliters", "centilitre", "centilitres")
        add(UnitVolume.deciliters, "dl", "deciliter", "deciliters", "decilitre", "decilitres")
        add(UnitVolume.liters, "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.cubicMeters, "m3", "m³", "cubic meter", "cubic meters", "cubic metre", "cubic metres")
        add(UnitVolume.gallons, "gal", "gallon", "gallons")
        add(UnitVolume.quarts, "qt", "quart", "quarts")
        add(UnitVolume.pints, "pt", "pint", "pints")
        add(UnitVolume.cups, "cup", "cups")
        add(UnitVolume.fluidOunces, "fl oz", "floz", "fluid ounce", "fluid ounces")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon", "tablespoons")
        add(UnitVolume.teaspoons, "tsp", "teaspoon", "teaspoons")
        kind = .speed
        add(exact("km/h", 1 / 3.6) as UnitSpeed, "km/h", "kmh", "kph")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s", "mps")
        add(UnitSpeed.knots, "kn", "kt", "knot", "knots")
        // Data, in decimal units as storage is sold; the binary ones by their own names.
        kind = .data
        add(UnitInformationStorage.bits, "bit", "bits")
        add(UnitInformationStorage.bytes, "b", "byte", "bytes")
        add(UnitInformationStorage.kilobytes, "kb", "kilobyte", "kilobytes")
        add(UnitInformationStorage.megabytes, "mb", "megabyte", "megabytes")
        add(UnitInformationStorage.gigabytes, "gb", "gigabyte", "gigabytes")
        add(UnitInformationStorage.terabytes, "tb", "terabyte", "terabytes")
        add(UnitInformationStorage.petabytes, "pb", "petabyte", "petabytes")
        add(UnitInformationStorage.kibibytes, "kib", "kibibyte", "kibibytes")
        add(UnitInformationStorage.mebibytes, "mib", "mebibyte", "mebibytes")
        add(UnitInformationStorage.gibibytes, "gib", "gibibyte", "gibibytes")
        add(UnitInformationStorage.tebibytes, "tib", "tebibyte", "tebibytes")
        add(UnitInformationStorage.kilobits, "kbit", "kilobit", "kilobits")
        add(UnitInformationStorage.megabits, "mbit", "megabit", "megabits")
        add(UnitInformationStorage.gigabits, "gbit", "gigabit", "gigabits")
        // Time. Foundation stops at hours; a day and a week are exact multiples.
        kind = .time
        add(UnitDuration.milliseconds, "ms", "millisecond", "milliseconds")
        add(UnitDuration.seconds, "s", "sec", "secs", "second", "seconds")
        add(UnitDuration.minutes, "min", "mins", "minute", "minutes")
        add(UnitDuration.hours, "h", "hr", "hrs", "hour", "hours")
        add(exact("d", 86_400) as UnitDuration, "d", "day", "days")
        add(exact("wk", 604_800) as UnitDuration, "wk", "week", "weeks")
        return table
    }()
}
