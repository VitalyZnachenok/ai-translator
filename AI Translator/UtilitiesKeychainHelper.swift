//
//  KeychainHelper.swift
//  AI Translator
//
//  Безопасное хранение секретов (API-токенов) в системном Keychain.
//

import Foundation
import Security
import os

enum KeychainHelper {
    private static let service = "com.vitaly.ai-translator.tokens"
    /// Аккаунт единого элемента, в котором хранятся ВСЕ токены сразу (JSON: [profileId: token]).
    /// Один элемент = один запрос доступа Keychain при старте вместо одного на каждый профиль.
    private static let combinedAccount = "all-profile-tokens"
    private static let logger = Logger(subsystem: "com.vitaly.ai-translator", category: "Keychain")

    // MARK: - Combined storage (все токены одним элементом)

    /// Сохраняет все токены профилей одним элементом Keychain. Пустые токены отбрасываются.
    /// Если итоговый набор пуст — элемент удаляется.
    @discardableResult
    static func setAllTokens(_ tokens: [String: String]) -> Bool {
        let filtered = tokens.filter { !$0.value.isEmpty }

        guard !filtered.isEmpty else {
            return deleteCombined()
        }

        guard let data = try? JSONSerialization.data(withJSONObject: filtered) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: combinedAccount
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain combined add failed: \(addStatus)")
            }
            return addStatus == errSecSuccess
        }

        logger.error("Keychain combined update failed: \(updateStatus)")
        return false
    }

    /// Читает все токены одним обращением. Возвращает пустой словарь, если элемента нет.
    static func allTokens() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: combinedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }

        return dict
    }

    @discardableResult
    static func deleteCombined() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: combinedAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Per-account storage (legacy, для миграции)

    /// Сохраняет (или обновляет) токен для указанного аккаунта (обычно profile.id).
    /// Пустая строка трактуется как удаление записи.
    @discardableResult
    static func setToken(_ token: String, for account: String) -> Bool {
        guard !token.isEmpty else {
            return deleteToken(for: account)
        }

        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed: \(addStatus)")
            }
            return addStatus == errSecSuccess
        }

        logger.error("Keychain update failed: \(updateStatus)")
        return false
    }

    /// Читает токен для аккаунта. Возвращает nil, если записи нет.
    static func token(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Удаляет токен для аккаунта.
    @discardableResult
    static func deleteToken(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
