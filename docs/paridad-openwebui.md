# Paridad de Conduit con Open WebUI

Decisión de Dani (17-11-2026): paridad **nativa**, sin WebView, y medida contra la **superficie entera
de la web** — imágenes, carpetas, conectores, ajustes, espacio de trabajo —, no contra una lista de
endpoints. Lo único que se queda fuera es la administración del servidor.

## Qué hay al otro lado

- Instancia: `chat.e-dani.com`, Open WebUI **0.12.3** (el `openwebui-src/` vendorizado es la misma
  versión, así que sirve de referencia).
- Es un fork de la casa: además de los routers de upstream trae `automations`, `calendar`, `skills`,
  `notifications`, `apps`, `search`, `terminals`, `scim` y `mfa`.
- Flags activos en el despliegue (`kubectl -n chat exec … env`): `ENABLE_API_KEYS`, `ENABLE_IMAGE_EDIT`,
  `ENABLE_IMAGE_GENERATION`, `ENABLE_PLUGINS`, `ENABLE_PYODIDE_FILE_PERSISTENCE`,
  `ENABLE_OAUTH_TOKEN_EXCHANGE`; apagados: `ENABLE_OLLAMA_API`, `ENABLE_WEBSOCKET_SUPPORT`.

## La superficie de la web (lo que el usuario ve, no solo lo que el backend sirve)

Dani (17-11): la paridad es con la **web entera** — imágenes, carpetas, conectores, ajustes, espacio de
trabajo —, no con una lista de endpoints suelta. Esta es la superficie que hay que llevar a la app.

Leído del fork vendored (`openwebui-src/`), que es la misma versión desplegada:

| Zona | Qué tiene |
|---|---|
| Barra lateral | Nuevo chat; buscador global (`Ctrl+K`) por chats, mensajes y notas, con filtros por carpeta/canal y creado/compartido; menú fijo (Notas, Espacio de trabajo, Automatizaciones, Calendario), reordenable; historial de chats con no leído, preview al pasar, renombrar con doble clic, archivar/borrar con Shift, arrastrar a carpeta; «marcar todo leído»; importar chats soltando JSON; crear carpeta; crear canal (DM/grupo/canal); notas fijadas reordenables; modelos fijados; menú de usuario con perfil, estado (emoji + mensaje), ajustes, salir |
| Carpetas | Crear, anidar, renombrar, mover carpetas y chats (arrastrar), marcar leída, exportar JSON, borrar con «borrar el contenido», y sección «compartidas» con chats de otros en solo lectura o escritura |
| Chat · entrada | Adjuntar ficheros/captura/página web/Files/Notes/Knowledge/Chats/Drive/OneDrive; permisos de herramientas (acceso total o pedir aprobación); selector de modelo con fijar, comparar varios, descargar/eject, controles propios del modelo; integraciones (tools y skills, valves, OAuth de servidores MCP, web search, imagen, intérprete de código); variables y valves del chat; comandos `/` (temp, compact, fork, status, model, compare, create skill, prompts, knowledge…); menciones `@` (knowledge, ficheros, modelos, URLs, YouTube); dictado y modo llamada; popover de contexto/cola/tareas; panel Controls (valves, system prompt, parámetros avanzados), Files y Overview; Artifacts; multi-modelo con «Merge Responses» (MoA) |
| Chat · mensajes | Ramas anterior/siguiente; editar, copiar, leer en voz alta (TTS), fork desde el mensaje, valorar con pulgar y comentario, continuar, regenerar, borrar; citas y fuentes; permitir/denegar tool calls; insertar en la nota cuando el chat viene de una nota |
| Chat · menú | Compartir (clonar o permitir respuestas), descargar JSON/texto/PDF, copiar, mover a carpeta, archivar, borrar, etiquetas, fijar, clonar, ir arriba |
| Notas | Lista con búsqueda, filtros creadas/compartidas, vista lista/cuadrícula, orden; crear e importar `.md`/`.txt`; editor markdown con autoguardado, título por IA y formato automático; adjuntar ficheros; grabar audio y transcribirlo; mejorar con IA; chat de la nota; compartir con permisos; fijar; descargar TXT/MD/PDF; borrar |
| Canales | Mensajes con adjuntos, captura, voz, respuesta y menciones; reacciones; hilos; fijar mensajes; editar/borrar; miembros (añadir/quitar); editar y borrar canal; webhooks; tarjetas de apps embebidas; silenciar; chat cifrado extremo a extremo |
| Automatizaciones | Lista con búsqueda, filtro activas/pausadas, última ejecución; crear/editar con schedule (una vez, horaria, diaria, semanal, mensual, propia), destino (chat nuevo, carpeta, canal) y modelo; activar/pausar; ejecutar ahora; clonar; importar/exportar; detalle con runs |
| Calendario | Vista mes/semana/día; calendarios con nombre y color, mostrar/ocultar, borrar; eventos con todo el día, ubicación, recordatorio, repetición y descripción; borrar |
| Espacio de trabajo · Modelos | Lista con búsqueda, filtro y orden; crear, importar/exportar JSON; editor con modelo base, system prompt, parámetros, controles, prompts sugeridos, knowledge/tools/skills, acceso, versiones, «Set as Production»; toggle; clonar; enlace |
| Espacio de trabajo · Conocimiento | Colecciones con descripción y acceso; añadir carpeta, ficheros, directorio, sincronizar directorio, página web, texto; explorar y renombrar/mover/borrar ficheros; colecciones externas en solo lectura; borrar colección |
| Espacio de trabajo · Prompts | Lista con etiquetas, crear, importar/exportar; copiar, toggle, editor con comando, contenido, acceso, versiones e historial, «Set as Production»; clonar |
| Espacio de trabajo · Skills | Lista con búsqueda y orden; crear; importar ficheros, carpeta o URL; exportar ZIP/JSON; editor con contenido, ficheros, versiones; toggle; clonar |
| Espacio de trabajo · Herramientas | Lista; crear; importar JSON; editor de código con versiones; Valves por herramienta; manifest de soporte; clonar |
| Playground | Chat multirrol, completions e **imágenes** (generar y editar con imagen adjunta, descargar) |
| Compartido y watch | `/s/{id}` público de solo lectura con clonar/forkear; `/watch?v=` redirige a YouTube en el chat |
| Ajustes · General | Tema, idioma, system prompt, y parámetros avanzados (stream, compactación, function calling, reasoning tags, seed, stop, temperatura, reasoning effort, max tokens, top_k/p/min_p, penalties, mirostat, num_ctx, think, keep_alive, custom) |
| Ajustes · Interfaz | Escala, tipografía, alto contraste, fondo, burbujas, usuario, widescreen, chat temporal por defecto, fade, markdown por rol, autogeneración de título/follow-ups/etiquetas, auto-copy, auto-scroll, colapsar código, preview al pasar, pestañas multi-modelo, PDF estilizado; ubicación; Enter vs Ctrl+Enter, rich text, compresión de imágenes |
| Ajustes · Personalización | Memorias: activar, listar/buscar, añadir, editar, borrar, borrar todas |
| Ajustes · Audio | Motor STT e idioma, auto-envío; motor TTS, voces, velocidad, auto-play |
| Ajustes · Conexiones | Conexiones OpenAI-compatibles propias: añadir, editar, borrar |
| Ajustes · Herramientas | Servidores OpenAPI de herramientas y terminales propios: añadir, editar, borrar, refrescar |
| Ajustes · Controles de datos | Importar/exportar chats, compartidos, archivar todos, borrar todos, gestor de archivos (listar y borrar) |
| Ajustes · Notificaciones | Permiso del navegador y sonido; webhooks: eventos y destinos, crear/editar/borrar, por defecto, test, activar |
| Ajustes · Cuenta | Foto, nombre, bio, género, fecha de nacimiento, variables de usuario; contraseña; MFA (estado, reemplazar autenticador, códigos de recuperación); API key (ver, crear, borrar) |
| Ajustes · Uso / Archivados / Atajos / Acerca de | Dashboard de uso; chats archivados (buscar, abrir, desarchivar, borrar, desarchivar todo); atajos reasignables; versión y novedades |
| Administración | Panel `/admin` (usuarios, grupos, funciones, evaluaciones, analítica) y las pestañas admin del modal (general, autenticación, interfaz, conexiones, modelos, subagentes, integraciones, apps, documentos, audio, **imágenes**, web, ejecución de código, pipelines, analítica, evaluaciones, base de datos) — fuera del móvil salvo que Dani lo pida |

Notas de la lectura del fork: `/home` está vacío en esta versión y enlaza a rutas que no existen; el
Playground no tiene guard de rol en la UI (solo lo oculta el menú); no hay acción «guardar en memoria»
por mensaje (la memoria se gestiona en Personalización y se inyecta); no hay UI de RSVP de eventos;
MoA es el botón «Merge Responses» tras comparar modelos; «Avanzado» no es pestaña propia, vive dentro
de General; MCP no tiene pantalla propia, aparece como servidor de herramientas en Integraciones.

## Inventario del backend (0.12.3)

Routers montados en `main.py` y qué es de móvil y qué de administración.

| Router | Rutas | Móvil / admin |
|---|---|---|
| `auths` `/api/v1/auths` | signin/signout/signup, perfil, timezone, password, api_key, `oauth/{provider}/token/exchange`, sesiones OAuth | móvil; `admin/*` y `/add` admin |
| `mfa` `/api/v1/auths/mfa` | status, challenge, enroll/start, enroll/confirm, verify, replace, recovery/codes, recover | móvil |
| chats `/api/v1/chats` | list/search/pinned/archived/shared, `{id}` (leer, escribir, pin, fork, clone, archive, share, unread, folder, compact, tags, messages), import, read, archive/unarchive all | móvil; `config`, `all/db`, `list/user/{id}`, `stats/*` admin |
| folders `/api/v1/folders` | CRUD, parent, expanded, access, read, shared | móvil |
| files `/api/v1/files` | subir, listar, buscar, count, contenido, `process/status`, rename, borrar | móvil; `DELETE /all` admin |
| knowledge `/api/v1/knowledge` | CRUD, search, search/files, ficheros (add/update/remove/batch/move), dirs, reindex, metadata/reindex, sync/diff, sync/cleanup, reset, export | móvil; `external/*` y `export` admin |
| models `/api/v1/models` | list, base, tags, model, history, profile/image, export, create, import, sync, update, access, toggle, delete | lectura móvil; escritura admin |
| prompts `/api/v1/prompts` | CRUD, history, tags, toggle, access, update/meta, update/version | mixto |
| tools `/api/v1/tools` | CRUD, specs, valves (propias/usuario), history, `load/url` | lectura móvil; autoría admin |
| functions `/api/v1/functions` | CRUD, valves, history, sync, toggle/global, `load/url` | admin |
| skills `/api/v1/skills` | CRUD, files, history, clone, toggle, access, import/preview, import, `load/url` | mixto (`workspace.skills`, `workspace.skills_import`) |
| pipelines `/api/v1/pipelines` | list, valves, upload, add, delete | admin |
| notes `/api/v1/notes` | CRUD, pinned, search, chat/`/chats`, pin, access | móvil |
| channels `/api/v1/channels` | CRUD, miembros, mensajes (post, pin, update, thread, data), reacciones, webhooks | móvil si `channels.enable` |
| apps `/api/v1/apps` | list, get, manifest/preview, create, patch, delete, connect, interactions | mixto |
| groups `/api/v1/groups` | list, info/preview/export, create, update, users add/remove, delete | casi todo admin |
| users `/api/v1/users` | self-service (`/user/*`, usage, permissions, status, variables), listado y gestión (`/{id}`, update, delete, revoke, groups, oauth/sessions), `default/permissions` | mixto |
| images `/api/v1/images` | config, models, config/update, verify, generations, edit | móvil (gen/edit); config admin |
| audio `/api/v1/audio` | config, models, voices, speech, transcriptions, WS realtime | móvil (speech/transcribe/voices); config admin |
| retrieval `/api/v1/retrieval` | embedding, config, process/{file,text,url,youtube,web,files/batch}, query/{doc,collection}, delete, reset | `process/*` y `query/*` móvil; resto admin |
| evaluations `/api/v1/evaluations` | leaderboard (+history), config, feedback (crear/leer/borrar), feedbacks/{user,list,models,all} | móvil el feedback; export/config admin |
| memories `/api/v1/memories` | listar, add, update, query, search, paths, path, reindex, reset, borrar usuario | móvil |
| tasks `/api/v1/tasks` | config, title/follow_up/tags/image_prompt/queries/auto/emoji/moa completions | móvil; `config/update` admin |
| notifications `/api/v1/notifications` | events, targets CRUD, target/test, target/default | móvil |
| automations `/api/v1/automations` | list, get, create, update, toggle, run, runs, delete | móvil |
| calendar `/api/v1/calendars` | calendarios CRUD/default, events CRUD/search/rsvp | móvil |
| search `/api/v1/search` | búsqueda global | móvil |
| analytics `/api/v1/analytics` | models, users, messages, summary, daily, tokens, por modelo | admin (`ENABLE_ADMIN_ANALYTICS`) |
| configs `/api/v1/configs` | export/import, connections, tool_servers, terminal_servers, code_execution, models, subagents, banners, suggestions, oauth/clients/register | admin salvo `models/defaults` y `banners` |
| utils `/api/v1/utils` | gravatar, db/download, code/format, code/execute | mixto (execute móvil) |
| terminals `/api/v1/terminals` | listar servidores, proxy de rutas, WS de sesión | admin/power-user |
| scim `/api/v1/scim/v2` | identidad SCIM 2.0 | IdP (`ENABLE_SCIM`) |
| `main.py` | `/api/chat/completions`, `/api/message(s)`, count_tokens, embeddings, chat/completed, chat/actions, models, tasks (list/chat/stop), `/api/config`, `/api/version`, `/api/events`, `/ws` | móvil; `/api/events/webhooks` admin |
| `openai` / `ollama` | gateways de proveedor: chat, modelos (descargar/cargar/descargar), config, catálogo | móvil el chat y el listado; el resto admin |

## Estado en la app, por área

Contrastado pantalla a pantalla con el código de la app (router `lib/core/router/app_router.dart`,
`lib/features/**`, y llamadas reales desde la UI a la capa de servicio). La app cubre más de lo que
parecía a primera vista: el hueco real es corto y está concentrado.

| Área de la web | En la app | Qué falta |
|---|---|---|
| Barra lateral | Drawer con pestañas Chats/Notas/Canales, fijados, archivados, árbol de carpetas, píldora de usuario y **buscador global** (`GET /api/v1/search`: chats, mensajes de canal y notas agrupados por tipo, con filtro de tipo) | Previsualización al pasar (es de escritorio) |
| Carpetas | Crear, renombrar, mover, marcar leída, exportar JSON, borrar con su contenido, anidar (subcarpetas en `/folder/:id`), mover un chat a carpeta, abrir compartidas, y ajustes de proyecto (prompt, conocimiento y modelos de la carpeta) | — |
| Chat · entrada | Adjuntos (fichero, fotos, cámara, página web, YouTube, ficheros del servidor), dictado y modo voz, comandos `/ # @ $`, selector de modelo con fijar y esfuerzo, cola de borradores, válvulas personales, comparar dos modelos con fusionar | Panel Controls con pestañas y Artifacts |
| Chat · mensajes | Ramas y paginador de versiones, editar, copiar, reintentar, continuar, bifurcar, escuchar/detener TTS, borrar, fuentes, ejecución de código, aprobar/denegar herramientas, uso de tokens, **valorar** con pulgar y motivo (`annotation` + evaluación, como `RateComment.svelte`) | — |
| Chat · menú | Fijar, archivar, compartir con audiencia, exportar JSON/Markdown, importar, borrar, clonar, **etiquetas** del chat (poner/quitar con sugerencias) y filtro de la lista por etiqueta | — |
| Notas | Lista con búsqueda y fijadas, editor, título y mejora por IA, adjuntos y audio, chat de la nota, compartir, fijar, borrar, guardar como propia | Importar `.md`/`.txt`, descargar TXT/MD/PDF, insertar una respuesta en la nota |
| Canales | Lista, canal, hilos, miembros (añadir/quitar/silenciar), reacciones, fijar, editar y borrar mensaje, crear y editar canal | Webhooks, chat cifrado, selector completo de reacciones |
| Automatizaciones | Lista con filtros, editor con schedule y destino, detalle con runs, activar/pausar, ejecutar ahora | Importar/exportar y clonar |
| Calendario | Agenda, calendarios con color y por defecto, eventos con repetición y asistentes, **RSVP** (la web no lo tiene) | Nada claro; recordatorios por confirmar |
| Espacio de trabajo | Modelos, Conocimiento, Prompts, Skills y Herramientas con editor completo: importar/exportar, clonar, versiones e historial, válvulas, accesos, subir ficheros y carpetas al conocimiento | **Etiquetas de prompts** como filtro (`GET /api/v1/prompts/tags`), sincronizar directorio (`/knowledge/{id}/sync/*`), importar skills por carpeta o URL, exportar skills en ZIP |
| Imágenes | Generación desde el compositor (marca en `/api/chat/completions`); modelo de imagen por defecto en Personalización; **Playground de imágenes**: crear desde un prompt o adjuntar fotos y editar, con los resultados en rejilla hasta compartirlos | Nada que la web tenga: su galería vive en memoria y solo la sirve a administradores, igual que en la app |
| Ajustes · General / Interfaz / Personalización / Audio / Datos / Notificaciones / Cuenta / Acerca de | Todas con pantalla; Notificaciones incluye destinos (webhooks) con test y por defecto; Controles de datos incluye exportar, importar, archivar todo y borrar todo | **Variables de usuario**, **atajos** reasignables, dashboard de **uso** (`GET /api/v1/users/usage`), **API key**, **MFA** |
| Conexiones e integraciones | Conexiones personales: servidores de herramientas (MCP) y terminales, con añadir/editar/activar/probar/borrar y API key propia | Paridad fina por tipo de conector (OAuth de servidores MCP) |
| Ficheros | Se suben, se adjuntan y hay selector de ficheros del servidor | **Gestor** con borrado desde la app, **estado de procesado para RAG** |
| Memorias | Listar, añadir, editar, borrar y limpiar en Personalización | Borrar todas y reindexar (`/memories/reset`, `/reindex`) |
| Compartido | Chat compartido de solo lectura (`/api/v1/chats/shared/{id}`) | Abrir un enlace público `/s/{id}` del servidor |
| Playground / Watch | Solo el playground de imágenes (fila Imágenes); el de chat y completions y Watch no existen | El resto del Playground es de administración; Watch es un atajo de escritorio |
| Administración | No existe | Fuera del móvil salvo que Dani lo pida |

## Tandas

Una PR por tanda; una tanda está hecha cuando su recorrido se puede usar en la app, no cuando la
llamada existe. Orden por valor de uso en el móvil, no por tamaño del endpoint.

**20-11, decisión de Dani:** la app deja de portar pantallas una a una. Conduit pasa a ser una
cáscara nativa (login, servidores, y después push/compartir) que abre la web real de Open WebUI con
la sesión de la app — el shell WebView, `OWU-144`. Las tandas T7–T11 se retiran: lo que piden ya lo
hace la web dentro del shell.

| Tanda | Qué | Dónde duele | Estado |
|---|---|---|---|
| T1 | Abrir el chat oculto de una nota | `POST /api/v1/notes/{id}/chat` | OWU-134, PR #20 |
| T2 | **Imágenes**: el playground de la web (crear desde un prompt o editar con fotos adjuntas, resultados en rejilla, compartir), sin inventar una galería que el servidor no tiene | `POST /api/v1/images/generations`, `POST /api/v1/images/edit` | OWU-134, PR #22 |
| T3 | **Carpetas**: marcar leída, exportar JSON y borrar con contenido | `POST /folders/{id}/read`, `GET /chats/folder/{id}`, `DELETE /folders/{id}?delete_contents=` | OWU-140 |
| T4 | **Conectores**: paridad fina de servidores de herramientas y terminales, incluido OAuth de MCP y prueba de conexión | `GET/POST /api/v1/tools/*`, `GET /api/v1/terminals`, OAuth del tool server | pendiente |
| T5 | **Valorar respuestas** (pulgar y motivo) y **etiquetas de chat** (poner, quitar, filtrar la lista por etiqueta) | `POST /api/v1/evaluations/feedback`, `/api/v1/chats/{id}/tags`, `GET /api/v1/chats/all/tags` | `OWU-141` |
| T6 | **Buscador global** con tipos (chats, mensajes, notas) y filtros | `GET /api/v1/search` | `OWU-142` |
| T7 | **Ajustes que faltan**: variables de usuario, atajos, uso, API key y MFA | `users/user/variables`, `users/user/settings/update` (`keybindings`), `GET /users/usage`, `/auths/api_key`, `/auths/mfa/*` | retirada — shell WebView (OWU-144) |
| T8 | **Ficheros**: gestor con borrado y estado de procesado para RAG | `GET /files/`, `DELETE /files/{id}`, `GET /files/{id}/process/status` | retirada — shell WebView (OWU-144) |
| T9 | **Espacio de trabajo fino**: etiquetas de prompts como filtro, sincronizar directorio, importar skills por carpeta o URL, exportar ZIP | `GET /prompts/tags`, `/knowledge/{id}/sync/*`, `/skills/import`, `/skills/export` | retirada — shell WebView (OWU-144) |
| T10 | **Notas**: importar `.md`/`.txt`, descargar TXT/MD/PDF e insertar una respuesta en la nota | `POST /notes/create` (por fichero), `GET /notes/{id}/chats` | retirada — shell WebView (OWU-144) |
| T11 | **Canales**: webhooks, chat cifrado y selector completo de reacciones | `/channels/{id}/webhooks*`, `/channels/{id}/encrypted` | retirada — shell WebView (OWU-144) |
| T12 | **Automatizaciones**: importar, exportar y clonar | `POST /automations/create`, `GET /automations/{id}` | pendiente |
| T13 | **Memorias**: borrar todas y reindexar | `POST /memories/reset`, `/reindex` | pendiente |
| T14 | **Compartido**: abrir un enlace público `/s/{id}` del servidor | `GET /chats/share/{share_id}` | pendiente |
| T15 | **Controls y Artifacts** del chat | — (local + settings) | pendiente |

Cada tanda lleva su prueba: el recorrido en la app real cuando haya dispositivo (`mac-casa` hoy no
tiene runtime de simulador utilizable) y, mientras no lo haya, widget test del menú o pantalla más
test del método de API.

Lo de administración (`analytics`, `pipelines`, `scim`, `configs`, `functions`, usuarios y grupos,
`utils`) no entra en ninguna tanda salvo que Dani lo pida. Los terminales y los servidores de
herramientas **no** son administración: son conectores de usuario y van en la T4.

### Cómo se comprueba

- Backend real: el fork desplegado es el vendored `openwebui-src/`; una ruta nueva se comprueba en el
  pod (`grep` del handler y `POST` sin token → 401, no 404).
- App: `flutter analyze` + la suite de la zona tocada. El build y los tests corren en `mac-casa`
  (`ssh mbpro`), porque en las máquinas del clúster no hay Flutter con los runtimes de simulador.