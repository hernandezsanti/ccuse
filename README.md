# claude-multi-account

Varias cuentas de Claude Code en la misma Mac, sobre **un solo config dir**. Elegí la que
tenga cupo al abrir una sesión, mirá el % de uso en el statusline, recibí un aviso al
llegar al umbral (95% por defecto) con el comando para cambiar de cuenta, y vé **todas** las
sesiones en background de todas las cuentas en el mismo FleetView.

## Cómo funciona

Una cuenta es solo una credencial. Todo lo demás (config, historial, sesiones, tareas,
skills, hooks, el daemon de background) vive en `~/.claude` y es común a todas.

Claude Code elige la credencial con `CLAUDE_SECURESTORAGE_CONFIG_DIR`: deriva el nombre
de la entrada de Keychain del string exacto de esa variable (`Claude Code-credentials` +
`-sha256(dir)[:8]`; sin sufijo si está vacía). Si no está, cae en `CLAUDE_CONFIG_DIR`.
Así que cada cuenta tiene un dir casi vacío (`~/.claude-<label>`) cuyo único rol es ser
ese string estable, y `ccuse <label>` lanza:

```bash
CLAUDE_CONFIG_DIR=<sin setear> CLAUDE_SECURESTORAGE_CONFIG_DIR=~/.claude-<label> claude
```

La cuenta default (`personal`, `~/.claude`) se lanza con la variable **vacía**, no
ausente: vacía pinea la credencial default aunque alguien haya dejado `CLAUDE_CONFIG_DIR`
exportado en el shell.

El % de uso sale de dos fuentes:

- **En vivo:** el statusline recibe `rate_limits.*.used_percentage` de Claude Code. Viene
  de los headers de cada respuesta del API, o sea por credencial: compartir config dir no
  mezcla el % entre cuentas.
- **Antes de arrancar:** `GET https://api.anthropic.com/api/oauth/usage` con el token de
  cada cuenta, leído de su entrada de Keychain.

### Por qué un solo config dir

Este repo empezó con un `CLAUDE_CONFIG_DIR` por cuenta y un sistema de symlinks para
compartir lo compartible. Lo que nunca se pudo compartir así fue el daemon de background,
y por lo tanto FleetView (el panel del `esc`): cada config dir corre su propio supervisor,
el mutex del roster es `<configDir>/daemon.lock` (fuera de `daemon/`), y el arranque hace
`unlink(control.sock)` sin condición, así que dos supervisores sobre un mismo roster se
roban el socket y se matan los workers mutuamente. Con un solo config dir hay un solo
supervisor y el problema desaparece.

Lo que hacía falta para invertir el modelo era que el daemon supiera con qué credencial
respawnear a cada worker. Lo hace: `CLAUDE_SECURESTORAGE_CONFIG_DIR` está en la allowlist
de `providerEnv` que persiste en `jobs/<id>/state.json` (junto a `CLAUDE_CONFIG_DIR`,
`AWS_PROFILE`, `GOOGLE_APPLICATION_CREDENTIALS`…). Verificado en vivo: dos jobs lanzados
bajo `~/.claude` con credenciales distintas quedaron con su propia credencial en
`providerEnv` y ambos autenticaron con la cuenta correcta.

## Componentes

| Archivo | Rol |
|---|---|
| `accounts.json` | Registro de cuentas (`label` → dir de credencial) y `threshold`. |
| `bin/cc-lib.sh` | Helpers: deps, expand, accounts, threshold, Keychain, token, `ccm_current_dir`. |
| `bin/cc-usage.sh <credDir>` | Consulta `/api/oauth/usage` → `% 5h/7d`. |
| `bin/cc-pick.sh [excluir]` | Elige la cuenta con menor uso bajo el umbral. |
| `bin/statusline.sh` | Barra de estado con cuenta, modelo, effort, contexto, `%` de uso, hora de reset y alerta. Guarda el último uso en `state/` para el hook. |
| `bin/stop-notify.sh` | Hook `Stop`: al terminar el turno, avisa si la cuenta activa está por quedarse sin cupo (lee `state/`, sin API). |
| `bin/cc-label.sh <credDir>` | Devuelve el label de una cuenta. |
| `bin/cc-new-account.sh <label>` | Da de alta una cuenta: dir de credencial + registro + comando de login. |
| `bin/cc-fleet.sh` | Sesiones en background de todas las cuentas, incluidas las del modelo viejo. Motor de `/fleet`. |
| `commands/fleet.md` | Slash command `/fleet`. Con un solo config dir el `esc` ya muestra todo; queda para la transición y para detectar jobs colgados. |
| `shell/claude-multi.sh` | Funciones `ccx`, `ccswitch`, `ccuse` y aliases `claude-<label>`. |

## Uso

```bash
ccx                  # abre Claude Code eligiendo la cuenta con cupo
ccswitch             # relanza en otra cuenta y retoma la conversación (al ver el ⚠️)
ccuse work     # abre una cuenta puntual por su nombre
claude-work    # alias equivalente a `ccuse work`
```

Los aliases `claude-<label>` se generan solos desde `accounts.json` al abrir la terminal.
Todo corre en un subshell: no deja variables pegadas en tu sesión.

El statusline muestra la cuenta **por credencial**, no por config dir:

```
client · Opus 5 · xhigh · ctx 19% · 5h 12% ↻23:50 · 7d 44% ↻06/07 05:00
```

Al cruzar el umbral agrega `⚠️ 95% — cambia de cuenta: ccswitch`. `ccswitch` sin
argumentos le inyecta `--continue` a `claude`, y como el historial es uno solo, retoma la
misma conversación en la otra cuenta. `CCM_NO_CONTINUE=1 ccswitch` abre sesión limpia.

### Aviso al terminar (hook Stop)

`stop-notify.sh` chequea el último uso registrado por el statusline y, si la cuenta activa
superó el umbral, muestra un aviso sugiriendo `ccswitch`. Cooldown de 300 s
(`CCM_NOTIFY_COOLDOWN`). Se cablea en `~/.claude/settings.json` bajo `hooks.Stop`.

## Setup

1. Dependencias (macOS): `jq curl security shasum`, y `bats-core` para los tests.
2. El statusline y el hook se cablean en `~/.claude/settings.json` (`statusLine.command`,
   `hooks.Stop`).
3. `source ~/projects/claude-multi-account/shell/claude-multi.sh` en `~/.zshrc`.
4. `ln -s ~/projects/claude-multi-account/commands/fleet.md ~/.claude/commands/fleet.md`.

### Agregar una cuenta

```bash
bin/cc-new-account.sh cliente              # dir de credencial: ~/.claude-cliente
bin/cc-new-account.sh cliente ~/otro/dir   # dir explícito
bin/cc-new-account.sh --check cliente      # diagnostica sin escribir
```

Crea el dir, registra la cuenta y, si no hay credencial en Keychain, imprime el comando de
login. El login sí va a mano, en una **terminal real** (no dentro de Claude Code):

```bash
CLAUDE_SECURESTORAGE_CONFIG_DIR="$HOME/.claude-cliente" claude    # adentro: /login, luego /exit
```

**No usar `CLAUDE_CONFIG_DIR` para loguear.** Loguear con la variable equivocada pisa la
credencial de otra cuenta sin avisar (#79223).

### Migrar desde el modelo viejo (un `CLAUDE_CONFIG_DIR` por cuenta)

No hay que re-loguear nada: la entrada de Keychain se deriva del mismo string que antes
iba en `CLAUDE_CONFIG_DIR`, así que `CLAUDE_SECURESTORAGE_CONFIG_DIR=~/.claude-work`
apunta a la misma credencial. Alcanza con reabrir la terminal.

Los `~/.claude-<label>` viejos quedan con symlinks vestigiales (`projects`, `sessions`,
`skills`…) que ya no lee nadie. Son inofensivos; se pueden borrar. Lo que sí sigue
importando en ellos es el path mismo: **no renombrarlos**, o la credencial deja de
resolver.

Las sesiones en background que arrancaron con el modelo viejo siguen en su daemon
por cuenta hasta que terminen. `/fleet` las ve; el `esc` de una sesión nueva no.

## Lo que queda compartido entre cuentas (y no era así antes)

Con un solo `.claude.json`: los MCP de scope user (antes había que replicarlos), la
lista de carpetas recientes, `tipsHistory`, el up-arrow (`history.jsonl`). Es lo que se
quería.

Y lo que se comparte **sin querer**, por bugs conocidos de Claude Code en este modo:

- **`/status` y el banner muestran la última cuenta que arrancó**, no la de la sesión
  (#79222). `oauthAccount` en `.claude.json` se reescribe en cada arranque. Es cosmético:
  billing, rate limits y refresh siguen a la credencial. El statusline de este repo sí
  dice la cuenta correcta.
- **`mcp-needs-auth-cache.json`** no está namespaceado (#87702): si un conector claude.ai
  falla auth en una cuenta, la otra lo salta 15 min aunque tenga token válido. Workaround:
  `rm -f ~/.claude/mcp-needs-auth-cache.json`.
- `policy-limits.json` lleva `compliance_taints` por org y queda el de la última cuenta.
  Sin síntoma conocido todavía.

El detalle y los issues a los que sumarse están en `docs/anthropic-issue-fleet-multi-account.md`.

## Tests

```bash
bats test/
```
