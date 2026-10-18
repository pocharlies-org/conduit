#!/usr/bin/env python3
"""El perfil de tienda y la firma manual de la exportación a TestFlight (DGX-883, P8b): lo llama testflight.sh.

  python3 Scripts/perfil-tienda.py --bundle ID --equipo TEAM --nombre NOMBRE --destino upload|export > opciones.plist

Por qué a mano. La firma automática de la exportación necesita el perfil de tienda GESTIONADO por Xcode, y la clave de App Store
Connect (rol App Manager) no puede crearlo: Apple contesta 403, resultCode 7495, sin acceso a certificados de distribución en la
nube (y, si pudiera, Xcode crearía un certificado nuevo, que el equipo no admite). Un perfil de tienda creado por API no es
«gestionado» y la firma automática no lo usa; la manual sí. Así que aquí, con la misma clave:

  1. se busca el certificado de distribución del equipo cuya clave privada está en el llavero de este Mac (nunca se crea uno);
  2. se busca el perfil IOS_APP_STORE de nombre fijo para este bundle id y ese certificado, o se crea (POST /v1/profiles);
  3. se instala como <UUID>.mobileprovision en los dos sitios donde Xcode mira: ~/Library/MobileDevice/Provisioning Profiles (el de
     siempre, el que midió IT con la exportación manual) y ~/Library/Developer/Xcode/UserData/Provisioning Profiles (el de Xcode 16
     en adelante);
  4. se escribe en stdout el plist de exportación con `signingStyle: manual`, el certificado y el perfil.

Es idempotente: un segundo run reutiliza el perfil. Un perfil del mismo nombre que ya no vale (invalidado, caducado o de otro
certificado) se borra antes de crear el nuevo: con el nombre ocupado no se puede crear. Solo esos; nada de otro nombre ni de otro
bundle id se toca. Las llamadas a App Store Connect van por Scripts/asc.sh, el único sitio que firma JWTs.
"""
import argparse
import base64
import datetime
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import urllib.parse

AQUI = pathlib.Path(__file__).resolve().parent
TIPO = "IOS_APP_STORE"
DISTRIBUCION = ("DISTRIBUTION", "IOS_DISTRIBUTION")
# Un perfil o un certificado que caduca en menos de esto no se usa: que no caduque a mitad de la subida.
MARGEN = datetime.timedelta(days=1)
PERFILES = (
    pathlib.Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles",
    pathlib.Path.home() / "Library" / "Developer" / "Xcode" / "UserData" / "Provisioning Profiles",
)


def fecha(texto):
    """Una fecha de App Store Connect (`2027-08-01T10:00:00.000+0000`, con Z o con dos puntos en el desfase) con su zona."""
    limpio = re.sub(r"\.\d+", "", texto).replace("Z", "+0000")
    return datetime.datetime.strptime(re.sub(r"([+-]\d\d):(\d\d)$", r"\1\2", limpio), "%Y-%m-%dT%H:%M:%S%z")


def asc(metodo, ruta, cuerpo=None, script=AQUI / "asc.sh"):
    """Una llamada a App Store Connect; su respuesta como JSON ({} si no trae cuerpo, como un DELETE)."""
    orden = ["bash", str(script), metodo, ruta] + ([json.dumps(cuerpo)] if cuerpo is not None else [])
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{metodo} {ruta.split('?')[0]}: {r.stderr.strip() or r.stdout.strip()}")
    return json.loads(r.stdout) if r.stdout.strip() else {}


def consulta(**parametros):
    # Los corchetes van codificados (curl los toma por un rango) y las comas no (varios valores de un filtro).
    return "?" + urllib.parse.urlencode(parametros, quote_via=urllib.parse.quote, safe=",")


def elegir_bundle(respuesta, identificador):
    """El id de recurso del bundle id EXACTO: el filtro de la API puede devolver parecidos."""
    return next((b["id"] for b in respuesta.get("data", []) if b["attributes"].get("identifier") == identificador), None)


def huella(certificado):
    """El SHA-1 del certificado en mayúsculas: lo mismo que `security find-identity` enseña del llavero."""
    return hashlib.sha1(base64.b64decode(certificado["attributes"]["certificateContent"])).hexdigest().upper()


def huellas_del_llavero(salida):
    """Las huellas de las identidades de firma de `security find-identity -v -p codesigning`."""
    return {h.upper() for h in re.findall(r"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s", salida, re.MULTILINE)}


def elegir_certificado(respuesta, del_llavero, ahora):
    """El certificado de distribución del equipo cuya clave privada está en este llavero; si hay varios, el que más dura."""
    validos = [
        c for c in respuesta.get("data", [])
        if c["attributes"].get("certificateType") in DISTRIBUCION and huella(c) in del_llavero
        and fecha(c["attributes"]["expirationDate"]) > ahora + MARGEN
    ]
    return max(validos, key=lambda c: fecha(c["attributes"]["expirationDate"]), default=None)


def elegir_perfil(respuesta, nombre, bundle, certificado, ahora):
    """De `GET /profiles?include=bundleId,certificates`: (el perfil que vale o None, los ids de los que ya no valen).

    Vale el ACTIVO de este nombre, de tienda, de este bundle id y de este certificado que no caduca pronto; entre varios, el que más
    dura. No valen los del MISMO nombre y bundle id que están invalidados, caducados o son de otro certificado. Lo demás no es nuestro."""
    buenos, viejos = [], []
    for p in respuesta.get("data", []):
        a, rel = p["attributes"], p.get("relationships", {})
        if a.get("name") != nombre or a.get("profileType") != TIPO:
            continue
        if ((rel.get("bundleId") or {}).get("data") or {}).get("id") != bundle:
            continue
        certificados = [c["id"] for c in (rel.get("certificates") or {}).get("data") or []]
        vale = a.get("profileState") == "ACTIVE" and certificado in certificados and fecha(a["expirationDate"]) > ahora + MARGEN
        (buenos if vale else viejos).append(p)
    elegido = max(buenos, key=lambda p: fecha(p["attributes"]["expirationDate"]), default=None)
    return elegido, [p["id"] for p in viejos]


def cuerpo_de_creacion(nombre, bundle, certificado):
    return {"data": {
        "type": "profiles", "attributes": {"name": nombre, "profileType": TIPO},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
            "certificates": {"data": [{"type": "certificates", "id": certificado}]},
        }}}


def instalar(perfil, directorios):
    contenido = base64.b64decode(perfil["attributes"]["profileContent"])
    for directorio in directorios:
        ruta = pathlib.Path(directorio) / (perfil["attributes"]["uuid"] + ".mobileprovision")
        ruta.parent.mkdir(parents=True, exist_ok=True)
        ruta.write_bytes(contenido)


def opciones_de_exportacion(destino, equipo, certificado, bundle, uuid):
    """El plist de `xcodebuild -exportArchive`. method=app-store-connect: sin él Xcode exporta como «development», que solo admite
    destination=export. manageAppVersionAndBuildNumber=false: el número de build es la cuenta de commits (Scripts/buildinfo.sh)."""
    return plistlib.dumps({
        "method": "app-store-connect", "destination": destino, "teamID": equipo, "signingStyle": "manual",
        "signingCertificate": certificado, "provisioningProfiles": {bundle: uuid}, "manageAppVersionAndBuildNumber": False,
    }, sort_keys=False)


def preparar(llamar, bundle, equipo, nombre, destino, del_llavero, ahora, directorios):
    """Deja instalado el perfil de tienda y devuelve el plist de exportación. `llamar` es `asc` (o un doble en las pruebas)."""
    id_bundle = elegir_bundle(llamar("GET", "/bundleIds" + consulta(**{"filter[identifier]": bundle, "limit": 200})), bundle)
    if id_bundle is None:
        raise SystemExit(f"{bundle} no existe como App ID en App Store Connect (aquí no se crea)")
    certificado = elegir_certificado(llamar("GET", "/certificates" + consulta(limit=200)), del_llavero, ahora)
    if certificado is None:
        raise SystemExit(
            "ningún certificado de distribución del equipo tiene su clave privada en este llavero: no se crean certificados, "
            "hay que instalar el que ya existe")
    existentes = llamar("GET", "/profiles" + consulta(**{
        "filter[name]": nombre, "filter[profileType]": TIPO, "include": "bundleId,certificates", "limit": 200}))
    elegido, viejos = elegir_perfil(existentes, nombre, id_bundle, certificado["id"], ahora)
    if elegido is None:
        for id_viejo in viejos:
            llamar("DELETE", f"/profiles/{id_viejo}")
        elegido = llamar("POST", "/profiles", cuerpo_de_creacion(nombre, id_bundle, certificado["id"]))["data"]
        print(f"perfil «{nombre}» creado ({elegido['attributes']['uuid']})", file=sys.stderr)
    else:
        print(f"perfil «{nombre}» reutilizado ({elegido['attributes']['uuid']})", file=sys.stderr)
    instalar(elegido, directorios)
    return opciones_de_exportacion(destino, equipo, huella(certificado), bundle, elegido["attributes"]["uuid"])


def main(argv=None):
    p = argparse.ArgumentParser(description="Prepara el perfil de tienda y escribe en stdout el plist de exportación con firma manual.")
    p.add_argument("--bundle", required=True)
    p.add_argument("--equipo", required=True)
    p.add_argument("--nombre", required=True)
    p.add_argument("--destino", required=True, choices=["upload", "export"])
    a = p.parse_args(argv)
    firmas = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True)
    if firmas.returncode != 0:
        raise SystemExit(f"security find-identity: {firmas.stderr.strip()}")
    ahora = datetime.datetime.now(datetime.timezone.utc)
    sys.stdout.buffer.write(
        preparar(asc, a.bundle, a.equipo, a.nombre, a.destino, huellas_del_llavero(firmas.stdout), ahora, PERFILES))


if __name__ == "__main__":
    main()
