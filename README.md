# claude-multi-account

Rotación de cuentas de Claude Code con detección de límite de uso.

Permite usar varias cuentas de Claude Code en la misma Mac, elegir automáticamente
la que tenga cupo al abrir una sesión, ver el % de uso en el statusline y recibir
un aviso al llegar al umbral (95% por defecto) con un comando para cambiar de cuenta.

## Cómo funciona

Cada cuenta es un **config dir** propio (`CLAUDE_CONFIG_DIR`). Claude Code deriva el
nombre de la entrada de Keychain a partir del path del config dir, así que cada cuenta
guarda sus credenciales por separado sin colisión. El % de uso sale de dos fuentes:

- **En vivo:** el statusline recibe `rate_limits.*.used_percentage` de Claude Code.
- **Antes de arrancar:** `GET https://api.anthropic.com/api/oauth/usage` con el token de cada cuenta.

## Componentes

| Archivo | Rol |
|---|---|
| `accounts.json` | Registro de cuentas (`label` → `configDir`) y `threshold`. |
| `bin/cc-lib.sh` | Helpers: deps, expand, accounts, threshold, Keychain, token. |
| `bin/cc-usage.sh <configDir>` | Consulta `/api/oauth/usage` → `% 5h/7d`. |
| `bin/cc-pick.sh [excluir]` | Elige la cuenta con menor uso bajo el umbral. |
| `bin/statusline.sh` | Barra de estado con modelo, effort, contexto, `%` de uso, hora de reset y alerta. Además guarda el último uso en `state/` para el hook. |
| `bin/stop-notify.sh` | Hook `Stop`: al terminar el turno, avisa si la cuenta activa está por quedarse sin cupo (lee `state/`, sin llamar a la API). |
| `bin/cc-label.sh <configDir>` | Devuelve el label de una cuenta. |
| `bin/cc-new-account.sh <label>` | Da de alta (o repara) una cuenta: config dir + symlinks compartidos + registro en `accounts.json`. |
| `bin/cc-mcp-sync.sh` | Replica los MCP server de scope user entre todas las cuentas (lo único que no se puede symlinkear). |
| `bin/cc-fleet.sh` | Sesiones en background de todas las cuentas, con liveness contra cada roster. Motor de `/fleet`. |
| `commands/fleet.md` | Slash command `/fleet`: la tabla de arriba dentro de la conversación, en cualquier cuenta. |
| `shell/claude-multi.sh` | Funciones `ccx`, `ccswitch`, `ccuse` y aliases `claude-<label>`. |

## Uso

```bash
ccx                  # abre Claude Code eligiendo la cuenta con cupo
ccswitch             # relanza en otra cuenta (asistido; al ver el ⚠️ en la barra)
ccuse work     # abre una cuenta puntual por su nombre
claude-work    # alias equivalente a `ccuse work`
claude-personal      # alias equivalente a `ccuse personal`
```

Los aliases `claude-<label>` se generan solos desde `accounts.json` al abrir la terminal.
Lanzar por cualquiera de estos comandos corre en un subshell, así que **no deja
`CLAUDE_CONFIG_DIR` pegado** en tu sesión.

El statusline muestra, por ejemplo:

```
personal · Opus 4.8 (1M context) · xhigh · ctx 19% · 5h 94% ↻23:50 · 7d 44% ↻06/07 05:00
```

donde `ctx` es el uso de la ventana de contexto, `5h`/`7d` el uso de cada límite,
y `↻` la hora a la que se resetea cada ventana. Al cruzar el umbral agrega
`⚠️ 95% — cambia de cuenta: ccswitch`.

### Aviso al terminar (hook Stop)

Cuando Claude termina de responder, el hook `stop-notify.sh` chequea el último uso
registrado por el statusline y, si la cuenta activa superó el umbral, muestra un aviso
sugiriendo `ccswitch`. No llama a la API (usa `state/`) y tiene cooldown
(`CCM_NOTIFY_COOLDOWN`, 300 s) para no repetirse en cada turno. Se cablea en
`~/.claude/settings.json` bajo `hooks.Stop`.

## Setup

1. Dependencias (macOS): `jq curl security shasum` y `bats-core` para los tests
   (`brew install bats-core`).
2. `accounts.json` ya trae `personal` (`~/.claude`) y `work` (`~/.claude-work`).
3. El statusline se cablea en `~/.claude/settings.json` (`statusLine.command`).
4. Las funciones de shell se cargan con `source ~/projects/claude-multi-account/shell/claude-multi.sh` en `~/.zshrc`.

### Loguear la segunda cuenta (work)

En una **terminal real** del sistema (no dentro de Claude Code):

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude   # adentro: /login, luego /exit
```

Verificar que la entrada de Keychain calculada coincide con la real:

```bash
source ~/projects/claude-multi-account/bin/cc-lib.sh
svc="$(ccm_keychain_service "$HOME/.claude-work")"
security find-generic-password -s "$svc" >/dev/null 2>&1 && echo "MATCH" || echo "NO MATCH"
```

Si da `NO MATCH`, buscar el nombre real y fijarlo en `accounts.json` con `"keychainService"`:

```bash
security dump-keychain 2>/dev/null | grep -o '"Claude Code-credentials[^"]*"' | sort -u
```

### Agregar una cuenta

Usar el script, **no crear el config dir a mano**:

```bash
bin/cc-new-account.sh cliente              # config dir: ~/.claude-cliente
bin/cc-new-account.sh cliente ~/otro/dir   # config dir explícito
```

Hace tres cosas: crea el config dir, tiende los symlinks compartidos hacia la cuenta
base (`~/.claude`), y registra la cuenta en `accounts.json` (con backup). Al final
imprime el comando de `/login`, que sí hay que correr a mano en una terminal real.

Antes de symlinkear rescata hacia la base lo que se perdería: los transcripts sueltos
de `projects/`, el registro de `sessions/` (si no, las sesiones vivas pierden su clave
de socket y dejan de responder a `SendMessage` hasta reiniciarlas), y el contenido de
`paste-cache/`, `tasks/`, `file-history/` e `image-cache/`. Los keyeados por sesión se
mergean **por archivo**, no moviendo el dir: la misma clave puede existir de los dos
lados, y ahí gana lo que ya estaba en la base.

La excepción es `.highwatermark` de `tasks/`, que guarda el último id entregado: ahí
"gana la base" dejaría la marca de una cuenta con las tareas de la otra, y la próxima
tarea pisaría una existente. Se resuelve por máximo, y el script corrige de paso
cualquier dir donde la marca haya quedado por debajo del mayor `<N>.json`.

Es **idempotente**: correrlo sobre una cuenta existente repone los links que falten,
así que también sirve de reparación. Lo que ya estaba se respalda como
`<item>.bak.<TS>`, nunca se borra. Si el config dir tenía transcripts sueltos en
`projects/`, los mueve a la cuenta base antes de symlinkear, para no perderlos.

```bash
bin/cc-new-account.sh --check cliente      # diagnostica, no escribe (exit 1 si falta algo)
bin/cc-new-account.sh --dry-run cliente    # muestra lo que haría
```

Un item que no exista en la base se saltea (`skip <item> (no existe en la base)`) en vez
de crear un symlink roto. Claude Code crea varios de esos dirs recién cuando los usa, así
que en una máquina nueva puede faltar alguno y esa cuenta queda sin compartirlo, en
silencio. Si `--check` lo reporta: `mkdir -p ~/.claude/<item>` y volver a correr el script.

#### Qué se comparte y qué no

Los symlinks que tiende (definidos en `ccm_shared_items`, en `bin/cc-lib.sh`):

```
.env  agents  commands  file-history  hooks  image-cache  paste-cache
plugins  projects  rules  sessions  settings.json  settings.local.json
skills  tasks
```

`sessions/` es el registro de peers: sin él, `ListAgents` y `SendMessage` solo ven
las sesiones de la propia cuenta. El transporte ya cruzaba cuentas — los sockets
viven todos en `/tmp/cc-socks` — así que lo único que faltaba era el descubrimiento.
No lleva credenciales: cada `<pid>.json` trae pid, cwd, nombre y estado, y cada
`<pid>.<hash>.key` un token atado a un socket concreto.

`tasks/`, `file-history/` e `image-cache/` van keyeados por sesión, igual que los
transcripts de `projects/`. Como `ccswitch` le inyecta `--continue` a `claude`, una
sesión cruza de cuenta por diseño; sin estos links cruza sin su lista de tareas, su
historial de undo ni sus imágenes pegadas, y la misma clave termina con medio estado
en cada config dir. `paste-cache/` es lo mismo para el texto pegado, pero keyeado por
hash de contenido.

Lo que queda **propio de cada cuenta**, y no hay que compartir: `.claude.json`
(el login OAuth), `history.jsonl` (el historial del up-arrow), `shell-snapshots/`,
`session-env/`, `cache/`, `backups/`, `telemetry/`, `policy-limits.json`,
`mcp-needs-auth-cache.json` y `stats-cache.json` (límites de org, auth de MCP y uso:
mezclarlos rompe el cálculo del statusline).

`daemon/` y `jobs/` tampoco, y este es el que más tienta: **FleetView queda separado por
cuenta y no hay forma de unificarlo**. Vale dejar escrito por qué, porque el intento es
razonable y falla de una manera que no se ve venir.

FleetView arma sus filas de `<configDir>/jobs/*/state.json`, reconciliadas contra
`<configDir>/daemon/roster.json` para saber qué sigue vivo. No usa el registro de
`sessions/`, que es lo que sí compartimos y por eso `ListAgents`/`SendMessage` sí cruzan.
No hay ningún punto donde el código recorra más de un config dir, y las env vars que
suenan a eso no lo hacen: `CLAUDE_CODE_FLEET_PAST_SESSIONS` solo agrega sesiones pasadas
y `CLAUDE_CODE_FLEETVIEW_SIMPLE` es un modo de render.

Lo que rompe el symlink de `daemon/` es que **el lock no vive adentro**: el mutex que
protege `roster.json` es `<configDir>/daemon.lock`, en la raíz del config dir. O sea que
symlinkear `daemon/` comparte el roster pero deja a cada cuenta con su propio lock, y los
dos supervisores se creen exclusivos a la vez. Peor: cuando uno toma el roster lo
reescribe con `workers: {}`, así que vacía los workers del otro, y después su barrido de
huérfanos los ve sin dueño y los mata.

Symlinkear solo `roster.json` tampoco: el daemon chequea que sea un archivo regular y lo
borra si no lo es. Y compartir solo `jobs/` deja filas sin reconciliar contra ningún
roster, y encima expone esos job dirs al barrido de huérfanos de la otra cuenta.

Hay una variante que "anda" en estado estable: compartir `daemon/` y `jobs/`, dejar cada
`daemon.lock` propio, y aliasar `/tmp/cc-daemon-<uid>/<hash(B)>` al de A. Tampoco: sin
lock compartido nada impide un segundo supervisor (reboot, self-upgrade, `/tmp` vaciado),
y el arranque hace `unlink(control.sock)` incondicional antes de escuchar, así que el
nuevo le roba el socket al viejo, adopta sus workers del roster y los dos se los matan.

#### La otra vía: un solo config dir con `CLAUDE_SECURESTORAGE_CONFIG_DIR`

Claude Code tiene una env var que invierte el diseño de este repo: **un solo config dir**
y solo la credencial separada. `CLAUDE_SECURESTORAGE_CONFIG_DIR` cambia de dónde se
deriva el nombre del servicio de Keychain (y el fallback `.credentials.json`) sin tocar
nada más. Verificado con un config dir vacío y descartable:

```bash
CLAUDE_CONFIG_DIR=/tmp/vacio claude auth status                        # loggedIn: false
CLAUDE_CONFIG_DIR=/tmp/vacio \
CLAUDE_SECURESTORAGE_CONFIG_DIR=~/.claude-client claude auth status  # loggedIn: true
```

Un config dir = un daemon = un FleetView. Sería la solución, y no lo es todavía por dos
cosas del binario (2.1.268):

- El daemon **no propaga esa variable** a los workers que lanza o respawnea: les inyecta
  solo `CLAUDE_CONFIG_DIR` y `CLAUDE_BG_ISOLATION`. Un job de la cuenta B respawneado
  corre con la credencial de A, gastando su cupo, sin aviso.
- `oauthAccount` en `.claude.json` no es decorativo: la resolución de org lo lee primero
  y solo va al API si falta, y se reescribe en cada arranque. Dos cuentas sobre un mismo
  `.claude.json` se pisan la org mutuamente.

El pedido a Anthropic está redactado en `docs/anthropic-issue-fleet-multi-account.md`.
Cuando lo arreglen, este repo pasa a ser un config dir con N credenciales y desaparece
casi todo el sistema de symlinks.

Mientras tanto, lo más cerca del TUI que se puede llegar es el slash command **`/fleet`**
(`commands/fleet.md`, symlinkeado en `~/.claude/commands/` y por lo tanto disponible en
todas las cuentas): lista las sesiones en background de todas las cuentas dentro de la
conversación. Su motor es `bin/cc-fleet.sh`, que lee `jobs/*/state.json` de cada cuenta
y reconcilia contra su `roster.json` para marcar `·muerta` lo que ya no tiene proceso.
Solo lectura, sin tomar ningún lock. No es la pantalla del `esc`, es lo que hay.

Saltearse este paso deja la cuenta a medias de una forma poco evidente: arranca y
funciona, pero sin statusline (falta `settings.json` → `statusLine.command`), sin
hooks, sin skills ni slash commands propios, y con `/resume` vacío porque
`projects/` no apunta al historial compartido. Ante la duda: `--check`.

## MCP servers

Es lo único que no se arregla con un symlink. Los MCP de scope user viven en
`<configDir>/.claude.json`, que queda propio de cada cuenta porque ahí está el OAuth,
así que un `claude mcp add` hecho en una cuenta es invisible desde las otras.

**`settings.json` no sirve para esto**, aunque su esquema acepte una clave `mcpServers`:
`claude mcp` no la lee. Un server definido ahí no aparece ni en `claude mcp list` ni en
`claude mcp get`, en silencio. No la uses.

```bash
bin/cc-mcp-sync.sh                    # unión de todas las cuentas → todas la tienen
bin/cc-mcp-sync.sh --from client    # replica solo los de esa cuenta
bin/cc-mcp-sync.sh --check            # diagnostica, no escribe (exit 1 si falta algo)
bin/cc-mcp-sync.sh --dry-run          # muestra los comandos
```

Escribe con `claude mcp add-json --scope user`, nunca editando `.claude.json` a mano:
son ~160 KB de estado que las sesiones vivas reescriben solas, y tocarlo por afuera se
pisa con ellas. Solo agrega lo que falte; si un nombre está definido distinto en dos
cuentas avisa y respeta la que ya estaba, porque puede ser una diferencia deliberada.

Esa es la razón para preferir `--from <label>`: un server puede ser legítimamente de una
sola cuenta. `aws-mcp`, por ejemplo, lleva el perfil de AWS de esa cuenta en su `env`, así
que replicarlo a las demás no tendría sentido.

## Revertir

Se hicieron backups con timestamp al cablear:

```bash
# restaurar settings.json y zshrc (elegí el .bak.<timestamp> correspondiente)
cp ~/.claude/settings.json.bak.<TS> ~/.claude/settings.json
cp ~/.zshrc.bak.<TS> ~/.zshrc
```

## Tests

```bash
bats test/
```

## Alcance

- `ccswitch` sin argumentos **retoma la conversación** del directorio actual en la otra
  cuenta: le inyecta `--continue` a `claude`. No hace falta copiar el transcript porque
  las cuentas comparten `~/.claude/projects` por symlink, y `--continue` elige la sesión
  más reciente de ese directorio, sin mirar a qué cuenta pertenece.
- Para abrir una sesión limpia en la otra cuenta: `CCM_NO_CONTINUE=1 ccswitch`, o pasarle
  tus propios argumentos (`ccswitch --model opus`).
- `ccx` y `ccuse` siguen abriendo sesión nueva.
