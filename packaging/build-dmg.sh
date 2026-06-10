#!/usr/bin/env bash
#
# build-dmg.sh — РЕЛИЗНАЯ сборка: подпись Developer ID + нотаризация + красивый DMG.
#
# Делает то же оформление, что и build-dmg-local.sh (фон, раскладка иконок,
# README внутри образа), но подписывает сертификатом «Developer ID Application»
# с защищённой меткой времени, затем нотаризует DMG у Apple и делает staple.
# Такой DMG запускается на любом Mac без предупреждений Gatekeeper.
#
# Требования (однократно):
#   • Сертификат «Developer ID Application» в связке ключей.
#   • Профиль notarytool в связке ключей. Создать один раз:
#       xcrun notarytool store-credentials "AITranslatorNotary" \
#           --apple-id "you@example.com" --team-id "AVSS84MH6D" \
#           --password "app-specific-password"
#
# Использование (из корня проекта ai-translator/):
#   ./packaging/build-dmg.sh
#
# Переменные окружения:
#   NOTARY_PROFILE   — имя профиля notarytool (по умолчанию AITranslatorNotary)
#   SIGN_IDENTITY    — точное имя сертификата (по умолчанию первый Developer ID Application)
#   SKIP_NOTARIZE=1  — собрать и подписать, но не нотаризовать (для проверки)

set -euo pipefail

PROJECT="AI Translator.xcodeproj"
SCHEME="AI Translator"
CONFIGURATION="Release"
APP_NAME="AI Translator"
VOL_NAME="AI Translator"
NOTARY_PROFILE="${NOTARY_PROFILE:-AITranslatorNotary}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DD_DIR="${BUILD_DIR}/DerivedData"
STAGING="${BUILD_DIR}/dmg-staging"
BACKGROUND_SRC="${SCRIPT_DIR}/assets/dmg-background.png"
README_SRC="${SCRIPT_DIR}/dmg-README.txt"

cd "${ROOT_DIR}"

# --- Сертификат Developer ID ---
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
	echo "ОШИБКА: не найден сертификат «Developer ID Application» в связке ключей." >&2
	echo "Создайте его в Xcode → Settings → Accounts → Manage Certificates." >&2
	exit 1
fi
echo "==> Подпись будет сделана сертификатом: ${SIGN_IDENTITY}"

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

echo "==> Подпись Developer ID (hardened runtime + secure timestamp)"
codesign --force --deep --options runtime --timestamp \
	--sign "${SIGN_IDENTITY}" "${APP_SRC}"
codesign --verify --deep --strict --verbose=2 "${APP_SRC}"

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
hdiutil create -srcfolder "${STAGING}" -volname "${VOL_NAME}" \
	-fs HFS+ -format UDRW -ov "${DMG_TMP}" >/dev/null

MOUNT_DIR="/Volumes/${VOL_NAME}"
hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
hdiutil attach "${DMG_TMP}" -noautoopen -mountpoint "${MOUNT_DIR}" >/dev/null

echo "==> Оформление окна (Finder / AppleScript)"
osascript <<EOF || echo "    предупреждение: оформление не применилось (нет доступа к автоматизации Finder)"
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

sync
hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || \
	(sleep 2 && hdiutil detach "${MOUNT_DIR}" -force >/dev/null 2>&1) || true

echo "==> Сжатие в финальный DMG"
rm -f "${DMG_FINAL}"
hdiutil convert "${DMG_TMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_FINAL}" >/dev/null
rm -f "${DMG_TMP}"

# DMG тоже подписываем Developer ID — чтобы staple лёг на подписанный образ.
echo "==> Подпись DMG"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_FINAL}"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
	echo ""
	echo "Готово (без нотаризации): ${DMG_FINAL}"
	echo "Для нотаризации запустите без SKIP_NOTARIZE."
	exit 0
fi

echo "==> Нотаризация (notarytool, профиль: ${NOTARY_PROFILE}) — это может занять пару минут"
xcrun notarytool submit "${DMG_FINAL}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "==> Staple"
xcrun stapler staple "${DMG_FINAL}"
xcrun stapler validate "${DMG_FINAL}"
spctl --assess --type open --context context:primary-signature -v "${DMG_FINAL}" || true

echo ""
echo "Готово (нотаризовано): ${DMG_FINAL}"
