# Paridad de Conduit con Open WebUI

Decisión de Dani (17-11-2026): paridad **nativa**, sin WebView. Una función del backend que la app no
cubra es un hueco a cerrar, salvo lo que sea administración pura de servidor.

## Qué hay al otro lado

- Instancia: `chat.e-dani.com`, Open WebUI **0.12.3** (el `openwebui-src/` vendorizado es la misma
  versión, así que sirve de referencia).
- Es un fork de la casa: además de los routers de upstream trae `automations`, `calendar`, `skills`,
  `notifications`, `apps`, `search`, `terminals`, `scim` y `mfa`.
- Flags activos en el despliegue (`kubectl -n chat exec … env`): `ENABLE_API_KEYS`, `ENABLE_IMAGE_EDIT`,
  `ENABLE_IMAGE_GENERATION`, `ENABLE_PLUGINS`, `ENABLE_PYODIDE_FILE_PERSISTENCE`,
  `ENABLE_OAUTH_TOKEN_EXCHANGE`; apagados: `ENABLE_OLLAMA_API`, `ENABLE_WEBSOCKET_SUPPORT`.

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

## Lo que la app ya llama

Inventario por grep de literales de ruta en `lib/` y `packages/`:

| Área | Endpoints usados |
|---|---|
| Chats | `/api/v1/chats/…` (listar, crear, buscar, archivar, compartir, fork, importar), `/api/chat/completions`, `/api/tasks/chat/…`, `/api/tasks/stop/task` |
| Carpetas | `/api/v1/folders/…`, `/api/v1/folders/shared` |
| Conocimiento y ficheros | `/api/v1/knowledge/…`, `/api/v1/knowledge/kb…`, `/api/v1/knowledge/search`, `/api/v1/files/…`, `/api/v1/files/search` |
| Notas | `/api/v1/notes/…`, `/api/v1/notes/search` |
| Prompts / modelos / herramientas / funciones / skills | `/api/v1/prompts/…`, `/api/models`, `/api/v1/models/…`, `/api/v1/tools/…`, `/api/v1/functions/…`, `/api/v1/skills/…` |
| Canales | `/api/v1/channels/…` |
| Usuarios y grupos | `/api/v1/auths/…`, `/api/v1/users/…`, `/api/v1/groups/…`, `/api/v1/users/permissions` |
| Memorias | `/api/v1/memories/…` |
| Imágenes | `/api/v1/images/generations` |
| Evaluaciones | `/api/v1/evaluations/feedback/…` |
| Automatizaciones y calendario | `/api/v1/automations/…`, `/api/v1/calendars/events/…` |
| Config | `/api/config`, `/api/v1/configs/suggestions` |

## El hueco

Primera pasada (grep de literales de ruta + lectura de las pantallas; se contrasta con el inventario del
código de la app). El backend está casi entero cubierto a nivel de recurso: la app ya llama a chats,
carpetas, ficheros, conocimiento, notas, prompts, tools, functions, skills, modelos, imágenes
(generación), memorias, evaluaciones, tareas, canales, calendario, automatizaciones, notificaciones,
grupos, usuarios, MFA, audio (voz y transcripción), retrieval (web/YouTube) y apps.

Lo que falta, por valor de uso en el móvil:

| # | Función | Endpoint | Estado |
|---|---|---|---|
| 1 | Editar una imagen generada | `POST /api/v1/images/edit` (`ENABLE_IMAGE_EDIT=true` en el despliegue) | sin UI: no hay ninguna referencia a edición de imagen |
| 2 | Crear un chat a partir de una nota | `POST /api/v1/notes/{id}/chat`, `GET /api/v1/notes/{id}/chats` | hecho en T1; `GET …/chats` (listar los que ya tiene) sigue sin usar |
| 3 | Estado de procesado de un fichero para RAG | `GET /api/v1/files/{id}/process/status` | sin llamada |
| 4 | Importar/clonar una skill | `POST /api/v1/skills/import`, `/import/preview`, `/id/{id}/clone` | sin llamada |
| 5 | Búsqueda global | `GET /api/v1/search` | sin llamada (solo la de chats) |
| 6 | Memorias: reset y reindex | `POST /api/v1/memories/reset`, `/reindex` | sin llamada |
| 7 | Tags de prompts | `GET /api/v1/prompts/tags` | sin llamada |
| 8 | Valorar una respuesta | `POST /api/v1/evaluations/feedback` | servicio `MessageRating` sin quien lo llame; el footer del mensaje declara `onLike`/`onDislike` y no los pinta |
| 9 | Etiquetas de chat | `/api/v1/chats/all/tags`, `/api/v1/chats/{id}/tags` | capa de servicio sí, ninguna pantalla |
| 10 | Elegir el modelo de imagen | `GET /api/v1/images/models` | la capa lo pide y ninguna pantalla lo usa |
| 11 | Borrar un fichero de la lista | `DELETE /api/v1/files/{id}` | solo lo usa la limpieza interna de la app |

Fuera de alcance por ser administración de servidor (no se lleva al móvil salvo que Dani lo pida):
`analytics`, `pipelines`, `scim`, `terminals`, `configs`, `functions` (autoría), gestión de usuarios y
grupos, `utils` (`code/format`, `db/download`).

## Tandas

Una PR por tanda; una tanda está hecha cuando su recorrido se puede usar en la app, no cuando la
llamada existe. Orden por valor de uso en el móvil, no por tamaño del endpoint.

| Tanda | Qué | Endpoints | Estado |
|---|---|---|---|
| T1 | Abrir el chat oculto de una nota | `POST /api/v1/notes/{id}/chat` | OWU-134, PR #20 |
| T2 | Valorar una respuesta (pulgar y motivo) | `POST /api/v1/evaluations/feedback`, `DELETE …/{id}` | pendiente |
| T3 | Etiquetas de chat: ver, poner y filtrar la lista | `/api/v1/chats/all/tags`, `/api/v1/chats/{id}/tags` | pendiente |
| T4 | Ficheros: estado de procesado y borrar | `GET /api/v1/files/{id}/process/status`, `DELETE /api/v1/files/{id}` | pendiente |
| T5 | Skills: importar, clonar e historial | `/api/v1/skills/import`, `/import/preview`, `/id/{id}/clone`, `/id/{id}/history` | pendiente |
| T6 | Prompts: etiquetas como filtro | `GET /api/v1/prompts/tags` | pendiente |
| T7 | Memorias: borrar todo y reindexar | `POST /api/v1/memories/reset`, `/reindex` | pendiente |
| T8 | Búsqueda global desde la barra | `GET /api/v1/search` | pendiente |
| T9 | Imágenes: editar una generada y elegir modelo | `POST /api/v1/images/edit`, `GET /api/v1/images/models` | pendiente |

Cada tanda lleva su prueba: el recorrido en la app real cuando haya dispositivo (`mac-casa` hoy no
tiene runtime de simulador utilizable) y, mientras no lo haya, widget test del menú o pantalla más
test del método de API.

Lo de administración (`analytics`, `pipelines`, `scim`, `terminals`, `configs`, `functions`, usuarios y
grupos, `utils`) no entra en ninguna tanda salvo que Dani lo pida.

### Cómo se comprueba

- Backend real: el fork desplegado es el vendored `openwebui-src/`; una ruta nueva se comprueba en el
  pod (`grep` del handler y `POST` sin token → 401, no 404).
- App: `flutter analyze` + la suite de la zona tocada. El build y los tests corren en `mac-casa`
  (`ssh mbpro`), porque en las máquinas del clúster no hay Flutter con los runtimes de simulador.