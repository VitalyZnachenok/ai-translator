//
//  ModelsCache.swift
//  AI Translator
//
//  Кэш списка моделей по идентификатору профиля.
//  Ключ строится из profile.id, поэтому токен не попадает в UserDefaults и кэш чистится при удалении профиля.
//

import Foundation

enum ModelsCache {
    private static func key(for profileId: String) -> String {
        "cached_models_\(profileId)"
    }

    static func load(for profileId: String) -> [OpenWebUIModel]? {
        guard let data = UserDefaults.standard.data(forKey: key(for: profileId)),
              let models = try? JSONDecoder().decode([OpenWebUIModel].self, from: data),
              !models.isEmpty else {
            return nil
        }
        return models
    }

    static func save(_ models: [OpenWebUIModel], for profileId: String) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: key(for: profileId))
    }

    static func clear(for profileId: String) {
        UserDefaults.standard.removeObject(forKey: key(for: profileId))
    }
}
