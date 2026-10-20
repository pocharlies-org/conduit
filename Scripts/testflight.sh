#!/usr/bin/env bash
# Sube la build de iOS a TestFlight desde el Mac de compilación (SC-2732): el único canal de la app. Es la adaptación de
# correo-ios (Scripts/testflight.sh) a este repo Flutter: sin xcodegen ni project.yml — el equipo y el bundle id se leen del
# project.pbxproj de Runner, su único sitio.
#
# Firma: todo manual y determinista. Los tres targets llevan CODE_SIGN_STYLE = Manual en el pbxproj con sus perfiles de tienda,
# que Scripts/perfil-tienda.py busca o crea por API e instala en el Mac (nunca crea certificados; la clave de ASC es rol App
# Manager: puede crear perfiles, la de Developer no). Xcode no gestiona nada en la nube: con la clave de Developer fallaba con
# "Authentication failed: bearer token" porque gestionar perfiles con App Groups exige crearlos y esa clave recibe 403.
#
# Subcomandos:
#   subir    archive Release + export destination=upload. Necesita ASC_KEY_ID/ASC_ISSUER_ID/ASC_PRIVATE_KEY y la ficha de la app.
#   ensayo   lo mismo con destination=export: archiva y exporta firmado sin subir nada.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PBX=ios/Runner.xcodeproj/project.pbxproj
TEAM="$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$PBX" | awk '{print $3}')"
# El primer PRODUCT_BUNDLE_IDENTIFIER del pbxproj es el de Debug (.debug): el de la tienda es el que no lleva sufijo.
BUNDLE="$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [A-Za-z0-9.]*' "$PBX" | awk '{print $3}' | grep -Ev '\.debug$|Widget|Share|RunnerTests' | head -1)"
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
  printf '%s' "$ASC_PRIVATE_KEY" | base64 -d > "$KEYFILE" 2>/dev/null || true
  # base64 -d de BSD no falla con un PEM crudo: sale con 0 y deja basura. Si no huele a PEM, se escribe el valor tal cual.
  grep -q "BEGIN" "$KEYFILE" || printf '%s' "$ASC_PRIVATE_KEY" > "$KEYFILE"
  grep -q "BEGIN" "$KEYFILE" || { echo "ASC_PRIVATE_KEY no es un .p8" >&2; exit 1; }
}

# Los tres targets se firman a mano (CODE_SIGN_STYLE = Manual en el project.pbxproj, rama SC-2732): la firma automática de Xcode
# necesita gestionar perfiles en la nube y la clave de ASC de CI no puede crearlos (403). El archive no habla con Apple: usa los
# perfiles instalados por perfil-tienda.py. Las extensiones llevan el sufijo de su bundle id en el nombre del perfil.
extensiones() {  # "bundle|nombre" por línea, Runner primero
  echo "$BUNDLE|$PERFIL"
  echo "$BUNDLE.ConduitWidget|${PERFIL/ App Store/ Widget App Store}"
  echo "$BUNDLE.ShareExtension|${PERFIL/ App Store/ Share App Store}"
}

# Sin sesión con ventana (runner/ssh), una keychain bloqueada hace saltar errSecInternalComponent sin dónde pulsar «Always
# Allow». La contraseña va por stdin a `security -i`, nunca por argv (en un Mac cualquiera ve los procesos de otro).
llavero() {
  local kc="$HOME/Library/Keychains/build.keychain-db" pass
  [[ -f "$kc" && -f "$HOME/asc-certs/.kc-pass" ]] || { echo "falta build.keychain o ~/asc-certs/.kc-pass" >&2; exit 1; }
  pass="$(cat "$HOME/asc-certs/.kc-pass")"
  pass="${pass//\\/\\\\}"; pass="${pass//\"/\\\"}"
  printf 'unlock-keychain -p "%s" %s\n' "$pass" "$kc" | security -i >/dev/null
  printf 'set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "%s" %s\n' "$pass" "$kc" | security -i >/dev/null
}

archivar() {
  local log app ver N
  N="$(git rev-list --count HEAD)"
  log="build/ios/archive-xcodebuild.log"; mkdir -p build/ios
  # mermaid_core (path en pubspec) vive en un submódulo: sin él, pub get cae en un clone limpio.
  git submodule update --init --depth 1 third_party/mermaid third_party/katex
  flutter pub get
  # Codegen como release.yml (app + packages que declaran build_runner): sin .g.dart/.freezed.dart el kernel del
  # Run Script de Xcode cae con "Error when reading '*.g.dart': No such file or directory".
  dart run build_runner build --delete-conflicting-outputs
  for dir in packages/*/; do
    if [ -f "$dir/pubspec.yaml" ] && grep -q '^  build_runner:' "$dir/pubspec.yaml"; then
      (cd "$dir" && dart run build_runner build --delete-conflicting-outputs)
    fi
  done
  # Prewarm de los native assets (hooks objective_c/pdfium): bajo xcodebuild fallan a veces —xcrun sale vacío con
  # muchos hooks en paralelo—; en un entorno limpio compilan y quedan cacheados en .dart_tool para el archive.
  flutter build ios --release --no-codesign --build-number="$N" || { echo "flutter build ios (prewarm) falló" >&2; exit 1; }
  # En Flutter el CFBundleVersion del Info.plist es $(FLUTTER_BUILD_NUMBER) (Generated.xcconfig), no
  # $(CURRENT_PROJECT_VERSION): hay que pasar los dos o la build sube con el número del pubspec.
  if ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -destination "generic/platform=iOS" -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath "$BUILD" \
    CURRENT_PROJECT_VERSION="$N" FLUTTER_BUILD_NUMBER="$N" archive >"$log" 2>&1; then
    echo "  log completo: $log" >&2; tail -30 "$log"; exit 1
  fi
  grep -E "^\*\*" "$log" | tail -2
  app="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist" 2>/dev/null || echo "?")"
  [[ "$ver" == "$N" ]] || { echo "  CFBundleVersion ($ver) != cuenta de commits ($N)" >&2; exit 1; }
}

exportar() {
  local options subir="" salida="" par
  options="$(mktemp)"
  # Un plist de exportación con los TRES perfiles: la App Store exige el perfil de cada target del archive.
  while IFS='|' read -r bun nom; do
    python3 Scripts/perfil-tienda.py --bundle "$bun" --equipo "$TEAM" --nombre "$nom" --destino "$1" > "$options.$bun"
  done < <(extensiones)
  python3 - "$options" "$1" "$TEAM" "$options.$BUNDLE" "$options.$BUNDLE.ConduitWidget" "$options.$BUNDLE.ShareExtension" <<'PY'
import plistlib, sys
salida, destino, equipo = sys.argv[1:4]
base = [plistlib.load(open(r, 'rb')) for r in sys.argv[4:]]
perfiles = {}
for d in base:
    perfiles.update(d['provisioningProfiles'])
plistlib.dump({"method": "app-store-connect", "destination": destino, "teamID": equipo, "signingStyle": "manual",
               "signingCertificate": base[0]["signingCertificate"], "provisioningProfiles": perfiles,
               "manageAppVersionAndBuildNumber": False}, open(salida, 'wb'))
PY
  rm -f "$options.$BUNDLE" "$options.$BUNDLE.ConduitWidget" "$options.$BUNDLE.ShareExtension"
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
  llavero
  # Los perfiles de los 3 targets, instalados ANTES del archive: la firma manual del archive los necesita en el Mac.
  # exportar los vuelve a pedir y perfil-tienda.py los reutiliza (idempotente).
  while IFS='|' read -r bun nom; do
    python3 Scripts/perfil-tienda.py --bundle "$bun" --equipo "$TEAM" --nombre "$nom" --destino export >/dev/null
  done < <(extensiones)
  say "archive (build $N)"
  archivar
  say "export (destination=$destino)"
  exportar "$destino"
  [[ "$destino" == upload ]] && al_grupo_interno "$appid" "$N"
}

# ASC no asigna sola al grupo interno la build subida: sin esto no se ve en TestFlight (medido
# 20-10 con la 1956). La build solo existe en la API tras el procesado (~10-20 min): se espera a
# VALID y se añade. Si no llega, aviso y verde — igual que whatsnew.sh en llm-status-ios.
al_grupo_interno() {
  local appid="$1" N="$2" B="" i st G
  for i in $(seq 1 30); do
    read -r B st < <(bash Scripts/asc.sh GET "/builds?filter%5Bapp%5D=$appid&filter%5Bversion%5D=$N" \
      | python3 -c 'import json,sys;d=json.load(sys.stdin).get("data",[]);print(("%s %s"%(d[0]["id"],d[0]["attributes"].get("processingState"))) if d else "")')
    [[ "$st" == "VALID" ]] && break
    B=""
    sleep 60
  done
  [[ -n "$B" ]] || { say "aviso: la build $N no quedó VALID en ASC en 30 min; añádela al grupo a mano"; return 0; }
  G="$(bash Scripts/asc.sh GET "/betaGroups?filter%5Bapp%5D=$appid" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin).get("data",[]);print(d[0]["id"] if d else "")')"
  [[ -n "$G" ]] || { say "aviso: sin grupo de pruebas para $appid"; return 0; }
  # El POST de la relación contesta 204 (cuerpo vacío) y asc.sh lo lee como «no es JSON»
  # aunque haya añadido la build (medido 20-10 con la 1958): se verifica por GET.
  bash Scripts/asc.sh POST "/betaGroups/$G/relationships/builds" "{\"data\":[{\"type\":\"builds\",\"id\":\"$B\"}]}" >/dev/null 2>&1 || true
  # filter[version] no está permitido en esta relación (400 medido 20-10 con la 1960): se busca el id.
  if bash Scripts/asc.sh GET "/betaGroups/$G/builds?limit=200" \
    | python3 -c "import json,sys;sys.exit(0 if any(b['id']=='$B' for b in json.load(sys.stdin).get('data',[])) else 1)"; then
    say "build $N en el grupo de pruebas"
  else
    say "aviso: no se pudo añadir la build $N al grupo ($G)"
  fi
}

case "${1:-subir}" in
  subir)  publicar upload ;;
  ensayo) publicar export ;;
  *) echo "uso: testflight.sh subir|ensayo" >&2; exit 2 ;;
esac
