# Упаковка в DMG

Два скрипта собирают **красивый** DMG (фон, раскладка иконок app → Applications,
двуязычный README внутри образа). Оба сначала собирают приложение без подписи,
затем подписывают вручную имеющимся сертификатом.

| Скрипт | Подпись | Нотаризация | Для чего |
| --- | --- | --- | --- |
| `build-dmg-local.sh` | Apple Development | нет | запуск на своих машинах |
| `build-dmg.sh` | Developer ID Application | да | распространение на любой Mac |

## Локальный DMG (быстро, без нотаризации)

```bash
./packaging/build-dmg-local.sh
```

Результат: `build/AI Translator <версия>.dmg`. На «чужом» Mac Gatekeeper
предупредит при первом запуске (правый клик → «Открыть» → «Открыть»).

## Релизный DMG (Developer ID + нотаризация)

### Однократно: профиль notarytool

Нужен сертификат **Developer ID Application** в связке ключей и
**app-specific password** (appleid.apple.com → Sign-In and Security →
App-Specific Passwords). Сохраните профиль один раз:

```bash
xcrun notarytool store-credentials "AITranslatorNotary" \
    --apple-id "ВАШ_APPLE_ID" \
    --team-id "AVSS84MH6D" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

### Сборка

```bash
./packaging/build-dmg.sh
```

Скрипт: собирает Release → подписывает Developer ID (hardened runtime +
secure timestamp) → создаёт красивый DMG → подписывает DMG → нотаризует →
делает staple → проверяет через `spctl`. Результат:
`build/AI Translator <версия>.dmg` — запускается на любом Mac без предупреждений.

Проверить сборку без нотаризации:

```bash
SKIP_NOTARIZE=1 ./packaging/build-dmg.sh
```

Переопределяемые переменные: `NOTARY_PROFILE` (имя профиля), `SIGN_IDENTITY`
(точное имя сертификата), `SKIP_NOTARIZE=1`.

## Что уже настроено в проекте

- `ENABLE_HARDENED_RUNTIME = YES` (обязательно для нотаризации).
- `ITSAppUsesNonExemptEncryption = false` в Info.plist (используется только HTTPS).
- `MACOSX_DEPLOYMENT_TARGET = 14.0` (macOS Sonoma и новее).

## Перед релизом

- **Иконка приложения**: в `Assets.xcassets/AppIcon.appiconset` заполнен не
  весь набор размеров — добавьте полный набор (или один 1024×1024).
- **Версия/сборка**: поднимайте `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION`.
