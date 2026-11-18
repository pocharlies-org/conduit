# Plan de ejecución · paridad de Conduit con la web de Open WebUI

Para lanzarlo **en vivo con el harness** (skill `company-cto`): una historia Jira por tanda, `en-vivo`,
asignada a Dani e In Progress, y una sesión que la ejecuta con su brief de cuatro líneas. No es una épica
asíncrona: la épica admite tres historias y esto son catorce PRs independientes.

Lo que se compara y por qué, en `docs/paridad-openwebui.md` (superficie entera de la web, no endpoints).

## 0. Estado de partida (17-11-2026)

| Hecho | Dato |
|---|---|
| Tronco | `pocharlies-org/conduit`, rama `main`, último squash `d014903c` |
| Hecho | T1 (chat de la nota, #20) y T2 (playground de imágenes, #22) |
| Pendiente | T3 a T15 de este documento: 13 PRs |
| CI | **No corre en el fork** (`ci.yml` está guardado a `cogwheel0/conduit`): la PR enseña «no checks reported» y se fusiona con la evidencia de la sesión |
| Compilar y probar | Solo en `mac-casa` (`ssh mbpro`), `export PATH="$HOME/flutter/bin:$PATH"`, Flutter 3.47.7 |
| Validar en dispositivo | En el **iPhone de Dani** (`iPhone Charlies`, iPhone 16 Pro Max, UDID `00008140-000429142813C01C`): `flutter run -d 00008140-…` desde `mac-casa` para instalarlo, y el MCP `iphone` (mobile-mcp + WDA, LaunchAgent `com.e-dani.iphone-mcp`) para tocarlo. **El 18-11, 08:02 CET, sigue `unavailable`** en `devicectl list devices`: tiene que estar emparejado con `mac-casa` y despierto (cable, o la misma LAN con modo desarrollador inalámbrico). El simulador no sirve: el único runtime instalado es iOS 17.5 y `conduit` necesita ≥26 |
| Tronco en rojo | `test/core/auth/api_auth_interceptor_test.dart` — 2 pruebas de «session renewal» fallan en `main` desde antes de la T2 |
| Textos | Toda clave nueva va en **los trece** `lib/l10n/app_*.arb`; `polish_localization_test` compara `app_en` con `app_pl` y pone el tronco en rojo si falta una (pasó en T1) |

## 1. Contrato común de cada sesión

Todo lo que sigue ya está aprendido y se copia tal cual al brief de cada historia.

**Herramientas y sitio**

```bash
export PATH="$HOME/flutter/bin:$PATH"          # en mac-casa
cd ~/proyectos/chat/conduit && git fetch origin
git worktree add .claude/worktrees/<KEY>-<tema> -b <KEY>-<tema> origin/main
cd .claude/worktrees/<KEY>-<tema> && git submodule update --init --recursive --depth 1
flutter pub get && (cd packages/conduit_core && flutter pub get)
(cd packages/conduit_core && dart run build_runner build --delete-conflicting-outputs)
dart run build_runner build --delete-conflicting-outputs   # raíz, también hace falta
flutter gen-l10n
```

El código se escribe en el clon de Linux (`~/proyectos/chat/conduit/.claude/worktrees/<KEY>-<tema>`) y se
prueba en `mac-casa` sobre la misma rama publicada: commit, `git push`, `git pull --ff-only` en `mbpro`,
`flutter analyze`, `flutter test <lo tocado>` y, antes de fusionar, la suite completa.

**Puertas antes de fusionar**

1. `flutter analyze` sin nada.
2. Pruebas de lo tocado en verde **y** la suite completa: solo pueden quedar en rojo las dos de
   `api_auth_interceptor_test` (ver S0), ninguna más.
3. La build instalada **en el iPhone** y el recorrido de los criterios hecho en el teléfono con el MCP
   `iphone`, con su captura en la PR. Si el teléfono no está disponible, la sesión **no fusiona**: para y lo
   dice.
4. Cada criterio de la historia probado y escrito en la PR con lo que lo demuestra (orden, salida o prueba).
5. Barrido de código muerto: un `Agent(subagent_type: "harness:barrido-codigo-muerto")` con el worktree y el
   tronco, que borra lo que el cambio dejó muerto y empuja a la rama de la PR.
6. `docs/paridad-openwebui.md` actualizado en la misma PR: la fila de su área y la de su tanda.
7. Fusionar en squash con `gh pr merge <n> -R pocharlies-org/conduit --squash` y borrar el worktree por su
   ruta exacta.

**Lo que no se toca**

- El servidor de Open WebUI, sus flags o su código: la paridad es de la app.
- Otras tandas: si el trabajo encontrado no está en la lista de criterios, es una historia nueva, no un añadido.
- La administración del servidor (`/admin`), el Playground de chat/completions y `/watch`: fuera de alcance.
- Un test que falla porque el comportamiento cambió se arregla; uno que se salta, no.

**Validar como lo usa un usuario: solo en el iPhone**

Conduit es una app de iPhone: el único dispositivo de validación es el iPhone de Dani. No hay emulador ni
prueba que lo sustituya. Cada tanda instala su build en el teléfono, la sesión la maneja con el MCP `iphone`
(mobile-mcp + WDA), recorre los criterios y deja la captura de cada uno en la PR. Si el teléfono no está
disponible, la PR se queda abierta con **deployed, NOT validated: iPhone unavailable**, la sesión para con
`PARA DANI:` y no fusiona.

**Un iPhone bloqueado no sirve.** Con la pantalla bloqueada el sistema no deja arrancar la app, WDA no
responde y las herramientas del MCP devuelven error de conexión. Antes de empezar el recorrido, la sesión
desbloquea el teléfono (contraseña de Dani, que no se escribe en ningún sitio) y lo deja despierto; si no
puede, no es un fallo de la app y no se anota como tal.

## 1.5 Antes de la ola 1: el teléfono listo

Esto se hace una vez, antes de lanzar S0, T3, T5 y T6, y se repite al principio de cada tanda si el teléfono
se ha ido.

**Estado el 18-11-2026, 08:02 CET**: la ola 1 está creada (`OWU-139`–`OWU-142`) pero **retenida**. Desde
`mac-casa`, `xcrun devicectl list devices` sigue dando `unavailable` para `iPhone Charlies`
(`00008140-000429142813C01C`), igual que el 17-11. Ninguna sesión de la ola 1 puede empezar el recorrido en el
teléfono hasta que salga `available`; `OWU-139` no lo necesita (es de pruebas) y puede ir sola.

**a) Que `mac-casa` lo vea**

```bash
ssh mbpro 'xcrun devicectl list devices | grep 00008140-000429142813C01C'
# tiene que decir `available`, no `unavailable`
```

Si dice `unavailable`: cable al Mac, teléfono desbloqueado y «Confiar en este ordenador», o la misma red
Wi-Fi con modo desarrollador inalámbrico activo (Ajustes → Privacidad y seguridad → Modo desarrollador).

**b) Que el perfil cubra el UDID** (comprobado el 18-11: ya lo cubre)

```bash
ssh mbpro 'for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*; do
  security cms -D -i "$f" 2>/dev/null | grep -q 00008140-000429142813C01C && \
  security cms -D -i "$f" | plutil -extract Name raw -; done'
```

Deben salir, entre otros, `iOS Team Provisioning Profile: com.e-dani.plaud-direct` y el comodín
`Q3AVWT9CS8.*`, ambos del equipo `Q3AVWT9CS8`, que es el del proyecto
(`ios/Runner.xcodeproj/project.pbxproj`, bundle de desarrollo `com.morenoibanez.chat.debug`). Si algún día no
sale ninguno, se añade el UDID en el portal de Apple con la cuenta del equipo (o con la clave de App Store
Connect que ya usan `asc.sh` y `testflight.sh`).

**c) Compilar, instalar y arrancar** (en `mac-casa`, sobre el worktree de la tanda)

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd ~/proyectos/chat/conduit/.claude/worktrees/<KEY>-<tema>
flutter pub get && flutter gen-l10n
flutter build ios --debug --device-id 00008140-000429142813C01C
xcrun devicectl device install app --device 00008140-000429142813C01C \
  build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008140-000429142813C01C \
  com.morenoibanez.chat.debug
```

`flutter run -d 00008140-000429142813C01C` sirve para depurar a mano, pero se queda colgado en primer plano:
para una sesión, las tres órdenes de arriba son el camino.

**d) Manejarlo con el MCP `iphone`** (mobile-mcp, `http://127.0.0.1:8814/mcp` en `mac-casa`, LaunchAgent
`com.e-dani.iphone-mcp`)

```text
mobile_list_available_devices              # el UDID tiene que estar y no decir unavailable
mobile_list_apps                           # com.morenoibanez.chat.debug instalada
mobile_launch_app  packageName=com.morenoibanez.chat.debug
mobile_take_screenshot                     # la captura que va a la PR
mobile_list_elements_on_screen             # qué hay en pantalla, sin adivinar coordenadas
mobile_click_on_screen_at_coordinates      # tocar
mobile_type_keys                           # escribir
mobile_press_button  BUTTON=HOME           # desbloquear / salir
mobile_get_device_logs  / mobile_list_crashes
```

La app no arranca ni WDA responde con el teléfono bloqueado: primero se desbloquea. Cada criterio se recorre
así y su captura se adjunta a la PR.

## 2. Historias, en orden de uso

Orden por valor en el móvil. La columna «PR» es una estimación de tamaño, no de horas.

### S0 · Reparar las dos pruebas rojas del tronco

- **Objetivo**: `api_auth_interceptor_test` en verde en `main`.
- **Borde**: solo esas dos pruebas y lo que la causa toca; nada de la paridad.
- **Criterio**: `flutter test test/core/auth/api_auth_interceptor_test.dart` → 27 en verde; la suite completa
  queda sin fallos.
- **Por qué primero**: mientras haya rojo conocido, cada tanda tiene que distinguir «falla por mí» de
  «fallaba ya», y eso se hace peor cada PR.
- **Tamaño**: S (un día de depuración como mucho).

### T3 · Carpetas: leída, exportar, borrar con contenido

- **Web**: la carpeta se marca leída (apaga su contador), se exporta a JSON y se borra «con su contenido».
- **Llamadas**: `POST /api/v1/folders/{id}/read` (`routers/folders.py:667`), `GET /api/v1/folders/{id}`
  (`:300`), los chats son `GET /api/v1/chats/folder/{id}`; `DELETE /api/v1/folders/{id}?delete_contents=true`
  (`:710`).
- **App**: `lib/features/navigation/views/folder_page.dart`, provisión de carpetas en
  `packages/conduit_core/lib/providers/`.
- **Criterios**:
  - [ ] `POST …/read` marca la carpeta y el contador no vuelve tras recargar → prueba del proveedor con
        adaptador falso y comprobación en el servidor desplegado con una carpeta propia.
  - [ ] Exportar escribe un JSON con los chats de la carpeta, con el mismo contenido que el del servidor
        (id, título, mensajes) → prueba que compara ambas respuestas.
  - [ ] Borrar con contenido pide confirmación, dice cuántos chats se van y los borra → prueba del
        proveedor y widget de la confirmación.
- **Riesgo**: borrar arrastra chats; la confirmación tiene que decir el número real, no «todos».
- **Tamaño**: M.

### T5 · Valorar una respuesta y etiquetas de chat

- **Web**: pulgar arriba/abajo con comentario; etiquetas por chat y filtro de la lista por etiqueta.
- **Llamadas**: `POST /api/v1/evaluations/feedback` (`evaluations.py:425`), `GET/POST/DELETE
  /api/v1/chats/{id}/tags` (`chats.py:2288/2308/2349`), `GET /api/v1/chats/all/tags` (`:1098`),
  `POST /api/v1/chats/tags` (`:1337`) para filtrar.
- **App**: `MessageRating` (`packages/conduit_core/lib/services/message_rating.dart`) lo usa la fila de
  acciones del mensaje; las acciones del mensaje viven en
  `lib/features/chat/widgets/`; el menú del chat y la lista, en `lib/features/navigation/`.
- **Criterios**:
  - [ ] Valorar con pulgar y comentario persiste y se ve al reabrir el chat → prueba del servicio +
        comprobación con `GET /api/v1/evaluations/feedbacks/user` en el servidor desplegado.
  - [ ] Poner y quitar etiquetas; el filtro de la lista las usa → prueba del proveedor y widget de la lista.
  - [ ] El filtro se puede quitar y la lista vuelve entera.
- **Tamaño**: M.

### T6 · Buscador global

- **Web**: `Ctrl+K`, busca chats, mensajes, notas y canales, con filtros (carpeta, canal, creado,
  compartido).
- **Llamada**: `GET /api/v1/search` (`search.py:425`), que la app llama con `searchWorkspace`
  (`api_service_search.dart`); `searchConversations`, `searchChats` y `searchMessages`
  (`api_service_chat_lists.dart`) buscan solo dentro de los chats.
- **App**: barra lateral (`lib/features/navigation/widgets/`).
- **Criterios**:
  - [ ] Buscar devuelve resultados por tipo, agrupados, y abrir uno lleva a su chat, nota o canal → prueba
        del servicio con el cuerpo real de `search.py` y prueba de widget del agrupado.
  - [ ] Los filtros de tipo se aplican y se quitan.
  - [ ] Sin resultados, se dice; con el servidor caído, se dice y no se deja la lista en blanco.
- **Tamaño**: M.

### T4 · Conectores: OAuth de MCP, terminales y probar conexión

- **Web**: servidores de herramientas y terminales propios: añadir, editar, activar, probar y OAuth para
  servidores MCP.
- **Llamadas**: `GET/POST /api/v1/tools/`, `GET /api/v1/terminals`, y el flujo OAuth del servidor de
  herramientas del fork (`ENABLE_OAUTH_TOKEN_EXCHANGE=true` en el despliegue).
- **App**: `lib/features/integrations/views/personal_connections_page.dart` y su editor.
- **Criterios**:
  - [ ] Un servidor MCP que exige OAuth se autoriza desde la app y queda conectado, sin salir a otra app a
        mano → comprobación en el servidor desplegado con un servidor MCP real y una captura de la lista con
        su estado.
  - [ ] «Probar conexión» dice el error del servidor tal cual, o OK.
  - [ ] Añadir y quitar un terminal propio.
- **Riesgo alto**: OAuth abre navegador; hay que usar el flujo del proyecto (enlace universal o
  `ASWebAuthenticationSession`) y el navegador lo conduce agent-jake en las pruebas, nunca Dani.
- **Tamaño**: L. Es la tanda con más incógnitas; si el OAuth del fork no está listo, se entrega el resto y
  se abre una historia para el OAuth con lo medido.

### T7a · Ajustes: variables de usuario, API key y uso

- **Web**: variables de usuario (texto, secreto), la API key propia (ver, crear, borrar) y el dashboard de
  uso.
- **Llamadas**: `GET/POST /api/v1/users/user/variables` (`users.py:648/658`), `GET/POST/DELETE
  /api/v1/auths/api_key` (`auths.py:1497/1522/1540`), `GET /api/v1/users/usage` (`users.py:713`).
- **App**: `lib/features/profile/views/account_settings_page.dart` y una pantalla de uso.
- **Criterios**:
  - [ ] Crear, ver y borrar la API key desde la app; la key se enseña una vez y no se guarda en el
        dispositivo → prueba del servicio y comprobación con `GET /api/v1/auths/api_key`.
  - [ ] Las variables de usuario se listan, se añaden y se borran, y un secreto no se imprime en claro.
  - [ ] Uso: tokens y mensajes del periodo, con su rango.
- **Riesgo**: enseñar una credencial es superficie de seguridad; el criterio de no guardarla es duro.
- **Tamaño**: M.

### T7b · Ajustes: atajos reasignables y MFA

- **Web**: atajos del teclado reasignables y la pantalla de MFA (estado, reemplazar autenticador, códigos de
  recuperación).
- **Llamadas**: ajustes del usuario (`/api/v1/users/user/settings`), y `routers/mfa.py` completo
  (`/status`, `/enroll/start`, `/enroll/confirm`, `/replace`, `/recovery/codes`, `/recover`).
- **Criterios**:
  - [ ] El estado del MFA se ve; matricular y reemplazar piden el código y el servidor lo acepta → prueba
        del servicio con el contrato de `mfa.py` y comprobación con `GET /api/v1/mfa/status`.
  - [ ] Los códigos de recuperación se enseñan una vez, con aviso de que no se vuelven a ver.
  - [ ] Desactivar MFA exige el código; sin él, el servidor manda y la app lo muestra.
- **Riesgo**: si se rompe a mitad, se puede dejar una cuenta sin segundo factor o bloqueada. Se prueba con
  una cuenta de prueba, nunca con `me@e-dani.com`.
- **Tamaño**: M. **Se puede aparcar sin parar la paridad**; va al final de la ola 2.

### T8 · Ficheros: gestor y estado de procesado

- **Web**: Controles de datos tiene gestor de archivos (listar, buscar, borrar) y cada fichero dice si ya
  está procesado para RAG.
- **Llamadas**: `GET /api/v1/files/` (`files.py:489`), `GET /api/v1/files/search` (`:514`), `DELETE
  /api/v1/files/{id}` (`:1023`), `GET /api/v1/files/{id}/process/status` (`:624`).
- **App**: `lib/features/profile/views/chat_data_controls_page.dart`.
- **Criterios**:
  - [ ] Listar con búsqueda y paginación del servidor; borrar uno y verlo desaparecer.
  - [ ] El estado de procesado se ve y se refresca sin cerrar la pantalla (evento o recarga explícita, no
        un sondeo en bucle).
- **Tamaño**: M.

### T9 · Espacio de trabajo: etiquetas de prompt, sincronizar directorio, skills en ZIP

- **Web**: filtro por etiquetas de prompt; «sincronizar directorio» en conocimiento; importar skills de una
  carpeta o URL y exportarlas en ZIP.
- **Llamadas**: `GET /api/v1/prompts/tags` (`prompts.py:64`), `POST /api/v1/knowledge/{id}/sync/diff` y
  `/sync/cleanup` (`knowledge.py:1875/1995`), `POST /api/v1/skills/create` (`skills.py:219`),
  `GET /api/v1/skills/export` (`:164`).
- **App**: `lib/features/workspace/views/prompts/`, `…/knowledge/`, `…/skills/`.
- **Criterios**:
  - [ ] El filtro por etiqueta de prompt usa las etiquetas del servidor.
  - [ ] Sincronizar un directorio de conocimiento enseña qué entra y qué se limpia, y no borra sin
        confirmación.
  - [ ] Exportar skills deja un ZIP que el servidor vuelve a importar (ida y vuelta comprobada).
- **Tamaño**: M.

### T10 · Notas: importar, descargar e insertar una respuesta

- **Web**: importar `.md`/`.txt`, descargar TXT/MD/PDF, e insertar en la nota la respuesta de su chat.
- **Llamadas**: `POST /api/v1/notes/create` (`notes.py:221`) con el contenido del fichero; descargar es del
  cliente; insertar es la respuesta del chat de la nota (`POST /api/v1/notes/{id}/chat`, ya en la app desde
  T1) más una escritura en el editor.
- **App**: `lib/features/notes/views/` y las acciones del mensaje en el chat.
- **Criterios**:
  - [ ] Importar un `.md` crea la nota con su título y su markdown, y no pierde líneas ni tablas → prueba
        con un fichero de ejemplo y comprobación del contenido guardado.
  - [ ] Descargar genera TXT, MD y PDF legibles del mismo contenido.
  - [ ] «Insertar en la nota» añade el texto al final de la nota abierta y el autoguardado lo persiste.
- **Tamaño**: M.

### T11 · Canales: webhooks y reacciones completas

- **Web**: webhooks del canal y el selector completo de reacciones (el cifrado extremo a extremo queda
  fuera: necesita diseño propio y el servidor lo sirve con websockets apagados).
- **Llamadas**: `GET/POST /api/v1/channels/{id}/webhooks*` (`channels.py:2131/2150`).
- **App**: `lib/features/channels/views/channel_page.dart`, `…/widgets/`.
- **Criterios**:
  - [ ] Crear un webhook de canal, verlo y borrarlo; el mensaje del bot llega al canal → comprobación en el
        servidor desplegado con un webhook real.
  - [ ] El selector de reacciones ofrece el mismo conjunto que la web y la reacción persiste.
- **Tamaño**: M.

### T12 · Automatizaciones: importar, exportar y clonar

- **Web**: exportar una automatización a JSON, importarla y clonarla.
- **Llamadas**: `POST /api/v1/automations/create` (`automations.py:208`); exportar y clonar son del
  cliente, como en la web.
- **App**: `lib/features/automations/views/`.
- **Criterios**:
  - [ ] La ida y vuelta JSON conserva schedule, destino y modelo, y el servidor acepta el importado.
  - [ ] Clonar crea una copia con nombre nuevo y sin duplicar runs.
- **Tamaño**: S.

### T13 · Memorias: borrar todas y reindexar

- **Llamadas**: `POST /api/v1/memories/reset` (`memories.py:478`), `POST /api/v1/memories/reindex`
  (`:444`).
- **App**: `lib/features/profile/views/personalization_page.dart` (memorias).
- **Criterios**:
  - [ ] «Borrar todas» pide confirmación escrita y deja la lista vacía tras recargar.
  - [ ] Reindexar dice cuándo termina o qué respondió el servidor.
- **Tamaño**: S.

### T14 · Abrir un enlace compartido `/s/{id}`

- **Web**: `/s/{id}` es un chat público de solo lectura, con clonar/forkear.
- **Llamadas**: `GET /api/v1/chats/shared/{share_id}` (la app ya abre compartidos de su cuenta).
- **App**: el enlace universal de `chat.e-dani.com` ya abre la app (OWU-134, criterio 5); falta enrutar
  `/s/<id>` a una vista de solo lectura, con y sin sesión.
- **Criterios**:
  - [ ] Tocar un enlace `/s/{id}` abre la app en ese chat, sin pedir sesión para leer.
  - [ ] «Clonar» lo convierte en un chat propio y navega a él.
- **Tamaño**: S.

### T15 · Panel Controls y Artifacts

- **Web**: panel de controles del chat (valves, system prompt, parámetros avanzados) y Artifacts (bloques
  HTML/SVG que se previsualizan y se abren).
- **App**: nada de eso existe; los parámetros avanzados viven en General y las válvulas, en el menú del
  modelo.
- **Criterios**:
  - [ ] Los controls del chat (válvulas de sesión y system prompt por chat) se editan y viajan en la
        petición → prueba que compara el cuerpo enviado con los campos de `chat_settings`.
  - [ ] Un bloque `html`/`svg` con documento completo se muestra en Ajustes del chat como artifact y se abre
        a pantalla completa.
- **Riesgo alto**: un artifact es HTML ajeno en la app. Necesita el WebView del proyecto, sin JavaScript
  puente ni cookies de la sesión, o no entra. **Decisión de Dani antes de empezar**: si el WebView no se
  quiere en la app, T15 se queda en la previsualización de SVG/imagen y se cierra así.
- **Tamaño**: L.

### Fuera de alcance (y por qué)

- Administración del servidor, Playground de chat/completions, `/watch`: son de escritorio o de admin.
- Cifrado extremo a extremo de canales: requiere diseño criptográfico propio y el despliegue sirve los
  canales con `ENABLE_WEBSOCKET_SUPPORT` apagado.
- Una galería de generaciones de imágenes: el servidor no la tiene; la de la web es memoria del navegador
  (ya replicada en T2).
- Modo offline nuevo, rediseño visual: no son paridad.

## 3. Olas

| Ola | Historias | Por qué así |
|---|---|---|
| 0 | S0 | quitar el rojo conocido antes de medir nada más |
| 1 | T3, T5, T6 | lo que se usa a diario: carpetas, valorar, buscar |
| 2 | T4, T7a, T8 | conectores y ajustes con credenciales |
| 3 | T9, T10, T11 | espacio de trabajo, notas, canales |
| 4 | T12, T13, T14, T7b | los pequeños |
| 5 | T15 | decisión de WebView antes |

Dos sesiones como máximo a la vez: `mac-casa` compila y prueba en serie, y dos ramas peleándose por el
mismo `build_runner` dan falsos rojos. Ola 1 admite dos en paralelo (T3 + T6) porque no comparten ficheros;
T5 toca el chat y va sola.

### 3.5 Tickets creados (18-11-2026)

Todas son `Task` en `OWU`, con `compania, en-vivo`, asignadas a Dani, In Progress y enlazadas con
`Relates OWU-134`.

| Clave | Tanda | Título | Brief de la sesión (cuatro líneas) |
|---|---|---|---|
| `OWU-139` | S0 | Devolver el tronco a verde: las dos pruebas de `api_auth_interceptor_test` | Deja en verde `test/core/auth/api_auth_interceptor_test.dart` en `main`. No toques la paridad ni nada más: lo que aparezca fuera es otra historia. Éxito = esa prueba y la suite completa sin fallos, con la causa escrita en la PR. Cuando termines, informa y para. |
| `OWU-140` | T3 | Carpetas: marcar leída, exportar a JSON y borrar con su contenido | Lleva a la app lo que la web hace con una carpeta: marcar leída, exportar a JSON y borrar con su contenido. No toques ninguna otra tanda. Éxito = los tres criterios recorridos en el iPhone con captura en la PR. Cuando termines, informa y para. |
| `OWU-141` | T5 | Valorar una respuesta y etiquetas de chat con su filtro | Añade valorar una respuesta y las etiquetas de chat con su filtro, como en la web. No toques el buscador ni las carpetas. Éxito = los tres criterios recorridos en el iPhone con captura en la PR. Cuando termines, informa y para. |
| `OWU-142` | T6 | Buscador global: chats, mensajes, notas y canales | Añade el buscador global sobre `/api/v1/search`, agrupado y con filtros. No toques ninguna otra tanda. Éxito = los tres criterios recorridos en el iPhone con captura en la PR. Cuando termines, informa y para. |

**Sin ticket todavía** (se abren al entrar en su ola, no antes): **T4**, **T7a**, **T7b**, **T8**, **T9**,
**T10**, **T11**, **T12**, **T13**, **T14** y **T15**. Son las once restantes; su ficha está en la sección 2
y no hace falta nada más para crearlas.

## 4. Cómo se lanza, paso a paso

1. **Crear la historia** de la tanda en Jira, proyecto `OWU`, tipo `Task`:

   ```
   summary: [Conduit] <lo que se entrega, en una línea>
   labels: ["en-vivo"]
   assignee: Dani · estado: In Progress
   description:
     Repo: /home/dibanez/proyectos/chat/conduit
     Objetivo: <la ficha de este documento, copiada>
     Borde: <lo que no se toca>
     Criterios: - [ ] … cada uno con la orden que lo prueba
     Enlace: Relates OWU-134 (la app que se está completando)
   ```

2. **Abrir la sesión** en el workspace de Conduit con el brief de cuatro líneas del harness: objetivo,
   borde explícito, criterio de éxito, y la última línea «cuando termines, informa y para». El contexto
   técnico va en la historia, no en el brief.
3. **La sesión** trabaja el contrato común de la sección 1, enseña cada criterio en la PR y fusiona en
   squash.
4. **Al terminar la tanda**, se marca su fila en `docs/paridad-openwebui.md` y se cierra la historia con la
   clave de la PR.

Para lanzar todo de golpe, una sesión por tanda de la ola 1 y las demás al cerrar la anterior: no catorce a
la vez.

## 5. Lo que espera a Dani

1. **T15 y el WebView.** ¿Entra un WebView para Artifacts, o se queda en SVG/imagen?
2. **MFA (T7b).** ¿Se hace con una cuenta de prueba en el servidor, o se deja fuera hasta que haya una?

Lo demás no se pregunta: el orden de la sección 3, el reparto en olas, la rama y el método de fusión son
los del plan y de las reglas.