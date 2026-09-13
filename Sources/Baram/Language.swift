import Foundation
import NaturalLanguage

struct AppLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let nativeName: String

    var locale: Locale.Language { Locale.Language(identifier: id) }
    static let auto = AppLanguage(id: "auto", name: "자동 감지", nativeName: "Detect language")
    static let common: [AppLanguage] = [
        .init(id: "ko", name: "한국어", nativeName: "한국어"),
        .init(id: "en", name: "영어", nativeName: "English"),
        .init(id: "ja", name: "일본어", nativeName: "日本語"),
        .init(id: "zh-Hans", name: "중국어 (간체)", nativeName: "简体中文"),
        .init(id: "zh-Hant", name: "중국어 (번체)", nativeName: "繁體中文"),
        .init(id: "es", name: "스페인어", nativeName: "Español"),
        .init(id: "fr", name: "프랑스어", nativeName: "Français"),
        .init(id: "de", name: "독일어", nativeName: "Deutsch"),
        .init(id: "it", name: "이탈리아어", nativeName: "Italiano"),
        .init(id: "pt", name: "포르투갈어", nativeName: "Português"),
        .init(id: "ru", name: "러시아어", nativeName: "Русский"),
        .init(id: "ar", name: "아랍어", nativeName: "العربية"),
        .init(id: "vi", name: "베트남어", nativeName: "Tiếng Việt"),
        .init(id: "th", name: "태국어", nativeName: "ไทย"),
        .init(id: "id", name: "인도네시아어", nativeName: "Bahasa Indonesia"),
        .init(id: "tr", name: "튀르키예어", nativeName: "Türkçe"),
        .init(id: "uk", name: "우크라이나어", nativeName: "Українська"),
        .init(id: "pl", name: "폴란드어", nativeName: "Polski"),
        .init(id: "nl", name: "네덜란드어", nativeName: "Nederlands")
    ]
    static func name(for code: String) -> String {
        if code == "auto" { return auto.name }
        return common.first { $0.id == code }?.name
            ?? Locale(identifier: "ko").localizedString(forLanguageCode: code) ?? code
    }
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
    static func target(for detected: String?, preferred: String, smart: Bool) -> String {
        smart ? (detected == "ko" ? "en" : "ko") : preferred
    }
}

struct TranslationRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let source: String
    let target: String
    let sourceCode: String
    let targetCode: String
}
