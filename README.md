# AI Translator

**English** · [Русский](#ai-translator-русский)

Smart menu‑bar translator for macOS that works with any OpenAI‑compatible API
(OpenWebUI, OpenAI, Ollama, OpenRouter, Anthropic‑compatible gateways, etc.).

## Features

- Translate between 16 languages with automatic source detection.
- Connect to any OpenAI‑compatible model through connection profiles.
- Custom prompts for different styles (literal, literary, technical, simplified…).
- Menu‑bar icon, quick popover and a full translator window.
- Two “quick translate” modes for selected text:
  - **Quick translate in a window** — opens a window with the result.
  - **In‑place translation** — replaces the selected text right inside the
    active app (works anywhere `⌘C`/`⌘V` works).
- Automatic clipboard save & restore.
- Auto‑swap of direction by detected language (e.g. `ru ↔ en`).
- Translation history (last 100) with search, copy and delete.
- API tokens are stored in the system Keychain, not in plain settings.
- Bilingual interface (English / Русский), switchable in Settings (restart applies it).

## Hotkeys

| Action | Default |
| --- | --- |
| Open translator window | `⌘O` |
| Open settings | `⌘,` |
| Quit | `⌘Q` |
| Quick translate selection (in a window) | configurable, default `⌘⇧T` |
| In‑place translation (replace selection) | configurable, default `⌘⇧T` |
| Cancel current in‑place translation | press the same hotkey again |

Both “quick” actions share the same default combo, so they can be reassigned
independently in Settings. If the combos collide, **in‑place translation** wins.

## In‑place translation

1. Select text in any app (Telegram, browser, IDE, Mail, …).
2. Press the configured hotkey.
3. The app simulates `⌘C`, sends the text to the active model, puts the result
   on the clipboard, simulates `⌘V`, then restores the original clipboard.

Enable **“use dedicated settings”** to always translate in‑place with a fixed
language/style; otherwise it reuses the last settings from the translator window.

### Auto‑swap by detected language

With **“auto‑swap by detected language”** enabled the app:

1. Detects the language of the selection locally via Apple’s Natural Language
   framework (no network).
2. Finds an active language pair containing that language.
3. Translates into the **other** language of that pair.

One pair `ru ↔ en` is active by default. Add any pairs (`ru ↔ de`, `en ↔ uk`,
…) or disable them individually. If the detected language isn’t in any active
pair, the regular `source/target` settings are used.

In‑place translation requires **Accessibility** permission — the app asks for
it on first launch.

## Requirements

macOS 14 (Sonoma) or newer (uses the Observation framework).

## Build & package

- Open `AI Translator.xcodeproj` in Xcode 15+ and run.
- Local styled DMG: `./packaging/build-dmg-local.sh` → `build/AI Translator <version>.dmg`.
- Notarized Developer ID DMG: see [`packaging/README.md`](packaging/README.md).

---

<a name="ai-translator-русский"></a>

# AI Translator (Русский)

[English](#ai-translator) · **Русский**

Умный переводчик для macOS в строке меню, работающий с любым
OpenAI‑совместимым API (OpenWebUI, OpenAI, Ollama, OpenRouter,
Anthropic‑совместимые шлюзы и т.п.).

## Возможности

- Перевод между 16 языками + автоопределение исходного.
- Подключение к любым OpenAI‑совместимым моделям через профили.
- Кастомные промпты для разных стилей перевода (буквальный, литературный,
  технический, упрощённый и т.д.).
- Иконка в menubar, быстрый popover и полноразмерное окно переводчика.
- Два режима «быстрого перевода» выделенного текста:
  - **Быстрый перевод в окне** — открывает окно с готовым результатом.
  - **Перевод на месте** — заменяет выделенный текст переводом прямо в
    активном окне (в любом приложении, где работает `⌘C`/`⌘V`).
- Автосохранение и восстановление содержимого буфера обмена.
- Автоматический обмен направлением по определению языка (`ru ↔ en`).
- История переводов (последние 100) с поиском, копированием и удалением.
- API‑токены хранятся в системном Keychain, а не в открытом виде в настройках.
- Двуязычный интерфейс (English / Русский), переключается в настройках
  (применяется после перезапуска).

## Горячие клавиши

| Действие | По умолчанию |
| --- | --- |
| Открыть окно переводчика | `⌘O` |
| Открыть настройки | `⌘,` |
| Выйти | `⌘Q` |
| Быстрый перевод выделенного текста (в окне) | настраивается, по умолчанию `⌘⇧T` |
| Перевод выделенного текста на месте (с заменой) | настраивается, по умолчанию `⌘⇧T` |
| Отмена текущего перевода на месте | повторное нажатие той же горячей клавиши |

Оба «быстрых» действия используют одну комбинацию по умолчанию, поэтому в
настройках их можно переназначить независимо. Если комбинации совпадают —
приоритет у «перевода на месте».

## Перевод на месте

1. Выделите текст в любом приложении (Telegram, браузер, IDE, Mail, …).
2. Нажмите настроенную горячую клавишу.
3. Приложение симулирует `⌘C`, отправляет текст в активную модель, кладёт
   результат в буфер, симулирует `⌘V` и восстанавливает исходный буфер.

Можно включить **«использовать собственные настройки»** — тогда перевод на
месте всегда выполняется с заранее заданными языком/стилем. Если выключено,
используются последние настройки из окна переводчика.

### Автоматический обмен направлением

При включённом **«Автоматический обмен по определению языка»** приложение:

1. Определяет язык выделенного текста локально через Apple Natural Language
   framework (без обращения к сети).
2. Ищет активную языковую пару, содержащую найденный язык.
3. Переводит текст в **другой** язык этой пары.

По умолчанию активна пара `ru ↔ en`. Можно добавить любые пары (`ru ↔ de`,
`en ↔ uk` и т.д.) или отключать их по отдельности. Если язык выделенного
текста не попадает ни в одну активную пару, используются обычные настройки
`source/target`.

Для работы требуется разрешение **Универсального доступа** (Accessibility) —
приложение запросит его при первом запуске.

## Требования

macOS 14 (Sonoma) или новее (используется Observation framework).

## Сборка и упаковка

- Откройте `AI Translator.xcodeproj` в Xcode 15+ и запустите.
- Локальный красивый DMG: `./packaging/build-dmg-local.sh` →
  `build/AI Translator <версия>.dmg`.
- Нотаризованный Developer ID DMG: см. [`packaging/README.md`](packaging/README.md).
