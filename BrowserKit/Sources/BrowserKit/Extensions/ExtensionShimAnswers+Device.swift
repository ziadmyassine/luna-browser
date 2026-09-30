import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import IOKit.pwr_mgt
import NaturalLanguage
import UserNotifications
import WebKit

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// The shim's calls about this Mac rather than the browser: its processors,
/// memory and displays, whether the person is at it, keeping it awake, its
/// fonts and voices, and its notifications.
extension ExtensionHost {

    func answerDeviceFamily(_ api: String, _ args: [Any], context: WKWebExtensionContext) async throws -> ShimAnswer? {
        switch String(api.prefix { $0 != "." }) {
        case "system": Self.answerSystem(api)
        case "idle", "power": answerPower(api, args.first, id: context.uniqueIdentifier)
        case "fontSettings": Self.answerFonts(api)
        case "i18n": api == "i18n.detectLanguage" ? ShimAnswer(Self.detectLanguage(args.first as? String ?? "")) : nil
        case "tts": ShimAnswer(ExtensionSpeech.shared.answer(api, args))
        case "notifications": await answerNotifications(api, args, context: context)
        default: nil
        }
    }

    private static func answerSystem(_ api: String) -> ShimAnswer? {
        switch api {
        case "system.cpu.getInfo":
            #if arch(x86_64)
            let (arch, model) = ("x86_64", "Intel")
            #else
            let (arch, model) = ("arm64", "Apple silicon")
            #endif
            return ShimAnswer([
                "numOfProcessors": ProcessInfo.processInfo.processorCount, "archName": arch, "modelName": model,
                "features": [String](), "processors": [Any](), "temperatures": [Double]()
            ])
        case "system.memory.getInfo":
            let capacity = Double(ProcessInfo.processInfo.physicalMemory)
            return ShimAnswer(["capacity": capacity, "availableCapacity": capacity / 2])
        case "system.storage.getInfo":
            return ShimAnswer([Any]())
        case "system.display.getInfo":
            return ShimAnswer(displays())
        default:
            return nil
        }
    }

    private func answerPower(_ api: String, _ first: Any?, id: String) -> ShimAnswer? {
        switch api {
        case "idle.queryState":
            return ShimAnswer(Self.idleState(threshold: (first as? Double) ?? 60))
        case "idle.getAutoLockDelay":
            return ShimAnswer(0)
        case "power.requestKeepAwake":
            keepAwake(id, display: (first as? String) == "display")
            return ShimAnswer(nil)
        case "power.releaseKeepAwake":
            shim.release(id)
            return ShimAnswer(nil)
        case "power.reportActivity":
            var assertion: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity(Self.assertionName, kIOPMUserActiveLocal, &assertion)
            return ShimAnswer(nil)
        default:
            return nil
        }
    }

    /// The Mac's fonts; the sizes are WebKit's defaults, which extensions may
    /// read and not change.
    private static func answerFonts(_ api: String) -> ShimAnswer? {
        switch api {
        case "fontSettings.getFontList":
            let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
            return ShimAnswer(families.filter { !$0.hasPrefix(".") }.map { ["fontId": $0, "displayName": $0] })
        case "fontSettings.getFont":
            return ShimAnswer(["fontId": "", "levelOfControl": "not_controllable"])
        case "fontSettings.getDefaultFontSize":
            return ShimAnswer(["pixelSize": 16, "levelOfControl": "not_controllable"])
        case "fontSettings.getDefaultFixedFontSize":
            return ShimAnswer(["pixelSize": 13, "levelOfControl": "not_controllable"])
        case "fontSettings.getMinimumFontSize":
            return ShimAnswer(["pixelSize": 0, "levelOfControl": "not_controllable"])
        default:
            return api.hasPrefix("fontSettings.set") || api.hasPrefix("fontSettings.clear") ? ShimAnswer(nil) : nil
        }
    }

    private func answerNotifications(_ api: String, _ args: [Any], context: WKWebExtensionContext) async -> ShimAnswer? {
        switch api {
        case "notifications.create":
            return ShimAnswer(await notify(args, context: context))
        case "notifications.clear":
            if let key = args.first as? String {
                let identifier = "\(context.uniqueIdentifier).\(key)"
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            }
            return ShimAnswer(true)
        case "notifications.getAll":
            return ShimAnswer([String: Any]())
        case "notifications.getPermissionLevel":
            return ShimAnswer("granted")
        case "notifications.update":
            return ShimAnswer(false)
        default:
            return nil
        }
    }

    private static let assertionName = "An extension in Luna" as CFString

    private func keepAwake(_ id: String, display: Bool) {
        shim.release(id)
        var assertion: IOPMAssertionID = 0
        let kind = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        if IOPMAssertionCreateWithName(kind as CFString, level, Self.assertionName, &assertion) == kIOReturnSuccess {
            shim.keepAwake[id] = assertion
        }
    }

    private static func idleState(threshold: Double) -> String {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool == true {
            return "locked"
        }
        let quiet = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return quiet >= threshold ? "idle" : "active"
    }

    /// Chrome's display info from Core Graphics: bounds in points, the main
    /// display first. The work area is the whole display: the menu bar and the
    /// Dock are the app's to know, and `NSScreen` is not BrowserKit's.
    private static func displays() -> [[String: Any]] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { display in
            let bounds = CGDisplayBounds(display)
            let pixels = CGDisplayCopyDisplayMode(display).map { Double($0.pixelWidth) } ?? bounds.width
            let scale = bounds.width > 0 ? pixels / bounds.width : 1
            let frame: [String: Double] = [
                "left": bounds.minX, "top": bounds.minY, "width": bounds.width, "height": bounds.height
            ]
            return [
                "id": String(display), "name": "", "isPrimary": CGDisplayIsMain(display) != 0,
                "isInternal": CGDisplayIsBuiltin(display) != 0, "isEnabled": true, "dpiX": 96 * scale, "dpiY": 96 * scale,
                "rotation": Int(CGDisplayRotation(display)), "bounds": frame, "workArea": frame
            ]
        }
    }

    private static func detectLanguage(_ text: String) -> [String: Any] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let guesses = recognizer.languageHypotheses(withMaximum: 3)
        return [
            "isReliable": (guesses.values.max() ?? 0) > 0.6,
            "languages": guesses.sorted { $0.value > $1.value }.map { ["language": $0.key.rawValue, "percentage": Int($0.value * 100)] }
        ]
    }

    /// The Mac's own notification, named for the extension.
    private func notify(_ args: [Any], context: WKWebExtensionContext) async -> String {
        let named = args.first as? String
        let options = (named == nil ? args.first : args.dropFirst().first) as? [String: Any] ?? [:]
        let key = named ?? UUID().uuidString
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        let name = context.webExtension.displayName ?? ""
        content.title = options["title"] as? String ?? name
        content.body = options["message"] as? String ?? ""
        content.subtitle = name
        let request = UNNotificationRequest(identifier: "\(context.uniqueIdentifier).\(key)", content: content, trigger: nil)
        try? await center.add(request)
        return key
    }
}

/// One voice for every extension that reads aloud.
@MainActor
final class ExtensionSpeech {

    static let shared = ExtensionSpeech()

    private let synthesizer = AVSpeechSynthesizer()

    private func speak(_ text: String, options: [String: Any]) {
        if !(options["enqueue"] as? Bool ?? false) { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        if let name = options["voiceName"] as? String {
            utterance.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == name }
        } else if let language = options["lang"] as? String {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        // Chrome's rate is a multiple of normal speed, 0.1 to 10.
        if let rate = options["rate"] as? Double {
            let wanted = Float(rate) * AVSpeechUtteranceDefaultSpeechRate
            utterance.rate = min(max(wanted, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        }
        if let pitch = options["pitch"] as? Double { utterance.pitchMultiplier = Float(min(max(pitch, 0.5), 2)) }
        if let volume = options["volume"] as? Double { utterance.volume = Float(min(max(volume, 0), 1)) }
        synthesizer.speak(utterance)
    }

    func answer(_ api: String, _ args: [Any]) -> Any? {
        switch api {
        case "tts.speak":
            speak(args.first as? String ?? "", options: args.dropFirst().first as? [String: Any] ?? [:])
            return nil
        case "tts.stop":
            synthesizer.stopSpeaking(at: .immediate)
            return nil
        case "tts.pause":
            synthesizer.pauseSpeaking(at: .immediate)
            return nil
        case "tts.resume":
            synthesizer.continueSpeaking()
            return nil
        case "tts.isSpeaking":
            return synthesizer.isSpeaking
        default:
            return AVSpeechSynthesisVoice.speechVoices().map { voice in
                ["voiceName": voice.name, "lang": voice.language, "remote": false, "eventTypes": ["start", "end"]] as [String: Any]
            }
        }
    }
}
