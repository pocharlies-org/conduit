#!/usr/bin/env bash
# API de App Store Connect con el JWT de esta casa: `Scripts/asc.sh GET|POST|PATCH <ruta> [json]` imprime la respuesta y falla
# si ASC contesta con `errors` o con algo que no es JSON (sin esto, un `data` ausente se lee como «no hay builds» y el dedupe de
# la subida se apagaría en silencio). Es el ÚNICO sitio del repo que firma JWTs de ASC; testflight.sh y whatsnew.sh lo llaman.
# Copia de llm-status-ios (Scripts/xcode-cloud.sh asc) sin la parte de Xcode Cloud, que aquí no existe (ARCHITECTURE.md).
#
# Necesita ASC_KEY_ID, ASC_ISSUER_ID y ASC_PRIVATE_KEY (el .p8 en base64, o el PEM tal cual): secretos del repo.
set -euo pipefail

ASC_KEY_ID="${ASC_KEY_ID:?falta ASC_KEY_ID (App Store Connect → Usuarios e integraciones → Claves de API)}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?falta ASC_ISSUER_ID}"
# Exportada: la lee el python de abajo por os.environ (sin export, KeyError y ningún JWT).
export ASC_PRIVATE_KEY="${ASC_PRIVATE_KEY:?falta ASC_PRIVATE_KEY (el .p8 en base64)}"
API="https://api.appstoreconnect.apple.com/v1"

KEYFILE="$(mktemp)"
trap 'rm -f "$KEYFILE"' EXIT

# El JWT (ES256) se firma con `openssl` y python3 de serie (en macOS y en el runner ARC): no hay `pip install` posible. El secreto
# llega en base64 (el .p8), en PEM o, si alguien guardó el DER crudo, en base64 de DER: las tres se dejan en PEM 0600.
python3 - "$KEYFILE" <<'PY'
import base64, os, sys
raw = os.environ["ASC_PRIVATE_KEY"].strip()
if "BEGIN" in raw:
    pem = raw
else:
    der = base64.b64decode(raw)
    try:
        pem = der.decode()
    except UnicodeDecodeError:
        b64 = base64.b64encode(der).decode()
        pem = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(b64[i:i+64] for i in range(0, len(b64), 64)) + "\n-----END PRIVATE KEY-----"
open(sys.argv[1], "w").write(pem + "\n")
os.chmod(sys.argv[1], 0o600)
PY

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# La firma de openssl sale en DER (SEQUENCE de dos INTEGER) y JWS pide los 64 bytes crudos r‖s.
token() {
  local now header payload signing sig
  now=$(date -u +%s)
  header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID")
  payload=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "$ASC_ISSUER_ID" "$now" "$((now + 1200))")
  signing=$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$KEYFILE" \
        | python3 -c '
import sys
der = sys.stdin.buffer.read()
i = 2 + (der[1] & 0x7F) if der[1] >= 0x80 else 2      # longitud de la SEQUENCE
def integer():
    global i
    n = der[i + 1]; v = der[i + 2:i + 2 + n]; i += 2 + n
    return v.lstrip(b"\0").rjust(32, b"\0")           # recorta el 0 de signo, rellena a 32
sys.stdout.buffer.write(integer() + integer())' \
        | b64url)
  printf '%s.%s' "$signing" "$sig"
}

metodo="${1:?uso: asc.sh GET|POST|PATCH|DELETE <ruta> [json]}"
ruta="${2:?uso: asc.sh GET|POST|PATCH|DELETE <ruta> [json]}"
cuerpo="${3:-}"
# El JWT va por stdin (`-H @-`), nunca en los argumentos: en el Mac de CI un usuario ve los procesos de otro (`ps`). `printf` es de
# bash y no lanza ningún proceso, así que no hay argv donde verlo. DELETE y el POST de una relación contestan 204 sin cuerpo:
# ahí «vacío» es el éxito (un error de ASC siempre trae JSON con `errors`).
printf 'Authorization: Bearer %s\n' "$(token)" \
  | curl -sS --connect-timeout 15 --max-time 60 --retry 3 -X "$metodo" "$API$ruta" \
      -H @- -H 'Content-Type: application/json' ${cuerpo:+-d "$cuerpo"} \
  | python3 -c 'import json,sys
t=sys.stdin.read()
if not t.strip() and sys.argv[1] in ("DELETE", "POST"):
    sys.exit(0)
try:
    d=json.loads(t)
except Exception:
    sys.exit("respuesta de App Store Connect que no es JSON: " + t[:300])
if isinstance(d, dict) and d.get("errors"):
    sys.exit("App Store Connect devolvió errores: " + json.dumps(d["errors"], ensure_ascii=False)[:600])
sys.stdout.write(t)' "$metodo"
