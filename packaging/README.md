# Упаковка и нотаризация (Developer ID → DMG)

Распространение вне Mac App Store: приложение подписывается сертификатом
**Developer ID Application**, проходит нотаризацию у Apple и упаковывается в `.dmg`.

## Однократная подготовка

1. **Сертификат.** В Xcode → Settings → Accounts → Manage Certificates создайте
   **Developer ID Application** (нужен платный аккаунт разработчика).
2. **Team ID.** Узнайте на developer.apple.com → Membership и впишите его в
   `packaging/ExportOptions.plist` (ключ `teamID`).
3. **App-specific password** для нотаризации: appleid.apple.com → Sign-In and Security →
   App-Specific Passwords.
4. **Сохраните профиль notarytool** (один раз):
   ```bash
   xcrun notarytool store-credentials "AITranslatorNotary" \
       --apple-id "you@example.com" \
       --team-id "YOURTEAMID" \
       --password "xxxx-xxxx-xxxx-xxxx"
   ```

## Сборка DMG

Из корня проекта (`ai-translator/`):

```bash
./packaging/build-dmg.sh
```

Скрипт: архивирует Release → экспортирует с Developer ID → создаёт DMG →
нотаризует → staple. Результат: `build/AI Translator-<версия>.dmg`.

### Локальная проверка без нотаризации

```bash
SKIP_NOTARIZE=1 ./packaging/build-dmg.sh
```

## Что уже настроено в проекте

- `ENABLE_HARDENED_RUNTIME = YES` (обязательно для нотаризации).
- `CODE_SIGN_STYLE = Automatic` — Xcode сам подберёт Developer ID при экспорте.
- `ITSAppUsesNonExemptEncryption = false` в Info.plist (используется только HTTPS).

## Открытые вопросы перед релизом

- **Иконка приложения**: в `Assets.xcassets/AppIcon.appiconset` заполнен только один
  размер. Добавьте полный набор (или один 1024×1024 для single-size), иначе иконка
  будет неполной.
- **Версия/сборка**: поднимайте `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION`
  перед каждым релизом.
