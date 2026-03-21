//
//  Localization.swift
//  Flint
//
//  Created by LC John on 2/2/25.
//

import Foundation

struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

public class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    @Published var currentLanguage: Language = .en

    static let supportedLanguages: [Language] = [
        .en,
        .zh,
        .zhHant,
    ]

    private init() {
        let savedLangCode = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        currentLanguage = Language.from(code: savedLangCode) ?? .en
    }

    func setLanguage(_ language: Language) {
        currentLanguage = language
        UserDefaults.standard.set(language.code, forKey: "selectedLanguage")
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}

extension Language {
    static let en = Language(code: "en", name: "English")
    static let zh = Language(code: "zh-Hans", name: "简体中文")
    static let zhHant = Language(code: "zh-Hant", name: "繁體中文")

    static func from(code: String) -> Language? {
        LocalizationManager.supportedLanguages.first { $0.code == code }  // 添加 LocalizationManager 前缀
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}
