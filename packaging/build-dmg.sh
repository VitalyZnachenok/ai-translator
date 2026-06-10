#!/usr/bin/env bash
#
# build-dmg.sh — сборка, подпись Developer ID, нотаризация и упаковка в DMG.
#
# Требования:
#   • Xcode и command line tools
#   • Сертификат "Developer ID Application" в связке ключей
#   • Сохранённый профиль notarytool (один раз):
#       xcrun notarytool store-credentials "AITranslatorNotary" \
#           --apple-id "you@example.com" --team-id "YOURTEAMID" \
#           --password "app-specific-password"
#
# Переменные окружения (можно переопределить перед запуском):
#   TEAM_ID            — Team ID (также пропишите в packaging/ExportOptions.plist)
#   NOTARY_PROFILE     — имя профиля notarytool (по умолчанию AITranslatorNotary)
#   SKIP_NOTARIZE=1    — пропустить нотаризацию (для локальной проверки сборки)
#
# Запуск из корня репозитория проекта:
#   ./packaging/build-dmg.sh

set -euo pipefail

# --- Параметры проекта ---
PROJECT="AI Translator.xcodeproj"
SCHEME="AI Translator"
CONFIGURATION="Release"
APP_NAME="AI Translator"

NOTARY_PROFILE="${NOTARY_PROFILE:-AITranslatorNotary}"

# --- Каталоги ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${SCRIPT_DIR}/ExportOptions.plist"

cd "${ROOT_DIR}"

echo "==> Очистка предыдущей сборки"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Архивирование (${CONFIGURATION})"
xcodebuild archive \
	-project "${PROJECT}" \
	-scheme "${SCHEME}" \
	-configuration "${CONFIGURATION}" \
	-archivePath "${ARCHIVE_PATH}" \
	-destination "generic/platform=macOS"

echo "==> Экспорт приложения (Developer ID)"
xcodebuild -exportArchive \
	-archivePath "${ARCHIVE_PATH}" \
	-exportOptionsPlist "${EXPORT_OPTIONS}" \
	-exportPath "${EXPORT_DIR}"

APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
	echo "ОШИБКА: не найден ${APP_PATH}" >&2
	exit 1
fi

# Версия для имени DMG
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "dev")"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "==> Создание DMG: ${DMG_PATH}"
DMG_STAGING="${BUILD_DIR}/dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
	-volname "${APP_NAME}" \
	-srcfolder "${DMG_STAGING}" \
	-ov -format UDZO \
	"${DMG_PATH}"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
	echo "==> Нотаризация пропущена (SKIP_NOTARIZE=1)"
	echo "Готово (без нотаризации): ${DMG_PATH}"
	exit 0
fi

echo "==> Нотаризация DMG (notarytool, профиль: ${NOTARY_PROFILE})"
xcrun notarytool submit "${DMG_PATH}" \
	--keychain-profile "${NOTARY_PROFILE}" \
	--wait

echo "==> Staple"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

echo ""
echo "Готово: ${DMG_PATH}"
