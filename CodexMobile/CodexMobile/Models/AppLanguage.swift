// FILE: AppLanguage.swift
// Purpose: App-wide language preference and lightweight manual localization helpers.
// Layer: Model
// Exports: AppLanguage, L

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    static let storageKey = "codex.appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var effectiveLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.preferredSystemLanguage
        case .english, .chinese:
            return self
        }
    }

    var title: String {
        switch self {
        case .system:
            return L("System Language", "系统语言")
        case .english:
            return L("English", "英文")
        case .chinese:
            return L("Chinese", "中文")
        }
    }

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }

        return language
    }

    private static var preferredSystemLanguage: AppLanguage {
        guard let identifier = Locale.preferredLanguages.first else {
            return .english
        }

        return identifier.hasPrefix("zh") ? .chinese : .english
    }
}

func L(_ en: String, _ zh: String) -> String {
    AppLanguage.current.effectiveLanguage == .chinese ? zh : en
}
