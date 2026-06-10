#!/usr/bin/env bash
#
# build-dmg-local.sh — сборка красивого DMG для ЛОКАЛЬНОГО использования.
#
# В отличие от build-dmg.sh (Developer ID + нотаризация) этот скрипт не требует
# сертификата Developer ID Application: приложение подписывается имеющимся
# сертификатом Apple Development. DMG получает фон, аккуратную раскладку иконок
# (приложение → Applications) и двуязычный README внутри образа.
#
# Использование (из корня проекта ai-translator/):
#   ./packaging/build-dmg-local.sh
#
# Переменные окружения:
#   DEVELOPMENT_TEAM — Team ID для стабильной подписи (по умолчанию 6R8PRCL539)

set -euo pipefail

PROJECT="AI Translator.xcodeproj"
SCHEME="AI Translator"
CONFIGURATION="Release"
APP_NAME="AI Translator"
VOL_NAME="AI Translator"
DEV_TEAM="${DEVELOPMENT_TEAM:-6R8PRCL539}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DD_DIR="${BUILD_DIR}/DerivedData"
STAGING="${BUILD_DIR}/dmg-staging"
BACKGROUND_SRC="${SCRIPT_DIR}/assets/dmg-background.png"
README_SRC="${SCRIPT_DIR}/dmg-README.txt"

cd "${ROOT_DIR}"

echo "==> Очистка"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Сборка приложения (${CONFIGURATION}, без подписи)"
xcodebuild build \
	-project "${PROJECT}" \
	-scheme "${SCHEME}" \
	-configuration "${CONFIGURATION}" \
	-derivedDataPath "${DD_DIR}" \
	-destination "generic/platform=macOS" \
	CODE_SIGNING_ALLOWED=NO \
	| grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

APP_SRC="${DD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
	echo "ОШИБКА: не найдена собранная .app: ${APP_SRC}" >&2
	exit 1
fi

# Подпись имеющимся сертификатом Apple Development (стабильная подпись для
# сохранения разрешений Keychain/Accessibility между сборками на этой машине).
SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')"
if [[ -n "${SIGN_ID}" ]]; then
	echo "==> Подпись: ${SIGN_ID}"
	codesign --force --deep --options runtime --timestamp=none \
		--sign "${SIGN_ID}" "${APP_SRC}"
	codesign --verify --deep --strict --verbose=1 "${APP_SRC}" || true
else
	echo "    предупреждение: сертификат Apple Development не найден — DMG будет с неподписанным приложением."
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_SRC}/Contents/Info.plist" 2>/dev/null || echo dev)"
DMG_FINAL="${BUILD_DIR}/${APP_NAME} ${VERSION}.dmg"
DMG_TMP="${BUILD_DIR}/tmp.dmg"

echo "==> Подготовка содержимого DMG"
rm -rf "${STAGING}"
mkdir -p "${STAGING}/.background"
cp -R "${APP_SRC}" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"
cp "${BACKGROUND_SRC}" "${STAGING}/.background/background.png"
cp "${README_SRC}" "${STAGING}/README.txt"

echo "==> Создание временного DMG"
hdiutil create \
	-srcfolder "${STAGING}" \
	-volname "${VOL_NAME}" \
	-fs HFS+ \
	-format UDRW \
	-ov "${DMG_TMP}" >/dev/null

MOUNT_DIR="/Volumes/${VOL_NAME}"
echo "==> Монтирование"
hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
hdiutil attach "${DMG_TMP}" -noautoopen -mountpoint "${MOUNT_DIR}" >/dev/null

echo "==> Оформление окна (Finder / AppleScript)"
STYLED=1
osascript <<EOF || STYLED=0
tell application "Finder"
	tell disk "${VOL_NAME}"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 150, 840, 600}
		set theViewOptions to the icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to 112
		set background picture of theViewOptions to file ".background:background.png"
		set position of item "${APP_NAME}.app" of container window to {145, 245}
		set position of item "Applications" of container window to {505, 245}
		set position of item "README.txt" of container window to {325, 372}
		update without registering applications
		delay 1
		close
	end tell
end tell
EOF

if [[ "${STYLED}" == "1" ]]; then
	echo "    оформление применено"
else
	echo "    предупреждение: не удалось применить оформление (нет доступа к автоматизации Finder)."
	echo "    DMG будет создан без раскладки иконок, но с фоном и README."
fi

sync
hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || \
	(sleep 2 && hdiutil detach "${MOUNT_DIR}" -force >/dev/null 2>&1) || true

echo "==> Сжатие в финальный DMG"
rm -f "${DMG_FINAL}"
hdiutil convert "${DMG_TMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_FINAL}" >/dev/null
rm -f "${DMG_TMP}"

echo ""
echo "Готово: ${DMG_FINAL}"
