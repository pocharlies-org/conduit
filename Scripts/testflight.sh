#!/usr/bin/env bash
# Sube la build de iOS a TestFlight desde el Mac de compilación (SC-2732): el único canal de la app. Es la adaptación de
# correo-ios (Scripts/testflight.sh) a este repo Flutter: sin xcodegen ni project.yml — el equipo y el bundle id se leen del
# project.pbxproj de Runner, su único sitio.
#
# Firma: archive con firma automática (identidad de desarrollo, perfiles gestionados por Xcode vía la clave de ASC con rol
# Developer) y exportación a mano con el perfil de tienda que Scripts/perfil-tienda.py busca o crea por API (nunca crea
# certificados). Las claves de ASC van SIEMPRE por ruta absoluta: xcodebuild no expande `~` (medido en SC-2732: con `~` literal
# da "Authentication failed: bearer token" y parece un problema de rol de la clave).
#
# Subcomandos:
#   subir    archive Release + export destination=upload. Necesita ASC_KEY_ID/ASC_ISSUER_ID/ASC_PRIVATE_KEY y la ficha de la app.
#   ensayo   lo mismo con destination=export: archiva y exporta firmado sin subir nada.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PBX=ios/Runner.xcodeproj/project.pbxproj
TEAM="$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$PBX" | awk '{print $3}')"
BUNDLE="$(grep -m1 -o 'PRODUCT_BUNDLE_IDENTIFIER = [A-Za-z0-9.]*' "$PBX" | awk '{print $3}')"
[[ -n "$TEAM" && -n "$BUNDLE" ]] || { echo "no encuentro DEVELOPMENT_TEAM o PRODUCT_BUNDLE_IDENTIFIER en $PBX" >&2; exit 1; }
PERFIL="e-Dani Chat App Store (CI)"
BUILD="build/ci"
ARCHIVE="build/ios/xcode/Runner.xcarchive"

say() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }

# El .p8 en un fichero 0600 (xcodebuild lo pide por ruta): base64 → PEM, o el PEM tal cual.
KEYFILE=""
keyfile() {
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY:-}" ]] || {
    echo "faltan ASC_KEY_ID/ASC_ISSUER_ID/ASC_PRIVATE_KEY" >&2; exit 1; }
  KEYFILE="$(mktemp)"; chmod 600 "$KEYFILE"
  trap 'rm -f "$KEYFILE"' EXIT
  printf '%s' "$ASC_PRIVATE_KEY" | base64 -d > "$KEYFILE" 2>/dev/null || printf '%s' "$ASC_PRIVATE_KEY" > "$KEYFILE"
  grep -q "BEGIN" "$KEYFILE" || { echo "ASC_PRIVATE_KEY no es un .p8" >&2; exit 1; }
}

archivar() {
  local log app ver N
  N="$(git rev-list --count HEAD)"
  log="$(mktemp)"
  if ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -destination "generic/platform=iOS" -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath "$BUILD" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEYFILE" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    CURRENT_PROJECT_VERSION="$N" archive >"$log" 2>&1; then
    tail -30 "$log"; rm -f "$log"; exit 1
  fi
  grep -E "^\*\*" "$log" | tail -2; rm -f "$log"
  app="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist" 2>/dev/null || echo "?")"
  [[ "$ver" == "$N" ]] || { echo "  CFBundleVersion ($ver) != cuenta de commits ($N)" >&2; exit 1; }
}

exportar() {
  local options subir="" salida=""
  options="$(mktemp)"
  python3 Scripts/perfil-tienda.py --bundle "$BUNDLE" --equipo "$TEAM" --nombre "$PERFIL" --destino "$1" > "$options"
  [[ "$1" == export ]] && salida="$BUILD/export"
  [[ "$1" == upload ]] && subir=1
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$options" ${salida:+-exportPath "$salida"} \
    ${subir:+-authenticationKeyPath "$KEYFILE" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"}
  rm -f "$options"
}

publicar() {
  local destino="$1" appid="" N
  keyfile
  N="$(git rev-list --count HEAD)"
  if [[ "$destino" == upload ]]; then
    appid="$(bash Scripts/asc.sh GET "/apps?filter%5BbundleId%5D=$BUNDLE" \
      | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["data"][0]["id"] if d.get("data") else "")')"
    [[ -n "$appid" ]] || { echo "no hay ficha para $BUNDLE en App Store Connect" >&2; exit 1; }
    local dupes
    dupes="$(bash Scripts/asc.sh GET "/builds?filter%5Bapp%5D=$appid&filter%5Bversion%5D=$N&filter%5BpreReleaseVersion.platform%5D=IOS" \
             | python3 -c 'import json,sys;print(len(json.load(sys.stdin).get("data", [])))')"
    [[ "$dupes" == "0" ]] || { say "la build $N ya está en ASC: nada que subir"; return 0; }
  fi
  say "archive (build $N)"
  archivar
  say "export (destination=$destino)"
  exportar "$destino"
  [[ "$destino" == upload ]] && say "subida: TestFlight la tendrá cuando ASC la procese (~10-20 min)."
}

case "${1:-subir}" in
  subir)  publicar upload ;;
  ensayo) publicar export ;;
  *) echo "uso: testflight.sh subir|ensayo" >&2; exit 2 ;;
esac
