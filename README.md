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
| `bin/statusline.sh` | Barra de estado con `%` y alerta al umbral. |
| `bin/cc-label.sh <configDir>` | Devuelve el label de una cuenta. |
| `shell/claude-multi.sh` | Funciones `ccx` y `ccswitch`. |

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

El statusline muestra, por ejemplo: `personal · 5h 94% · 7d 44%`. Al cruzar el umbral
agrega `⚠️ 95% — cambia de cuenta: ccswitch`.

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

### Agregar una tercera cuenta

Añadir una entrada a `accounts.json`:

```json
{ "label": "cliente", "configDir": "~/.claude-cliente" }
```

y loguearla con `CLAUDE_CONFIG_DIR="$HOME/.claude-cliente" claude`.

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

- **Fase 1 (actual):** `ccswitch` abre una **sesión nueva** en la otra cuenta.
- **Fase 2 (pendiente):** preservar el contexto copiando el transcript + `claude --resume`.
