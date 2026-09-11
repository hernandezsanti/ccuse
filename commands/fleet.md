---
description: Sesiones en background de TODAS las cuentas de Claude Code (lo que el panel de esc no puede mostrar). Opcional: --all para incluir las terminadas.
allowed-tools: Bash(~/projects/claude-multi-account/bin/cc-fleet.sh:*)
---

Sesiones en background de todas las cuentas ahora mismo:

```
!`~/projects/claude-multi-account/bin/cc-fleet.sh $ARGUMENTS`
```

Mostrá la tabla tal cual, sin resumirla ni reordenarla. Si hay filas marcadas `·muerta` con
estado `working`, señalalas aparte: son jobs que quedaron colgados (dicen estar trabajando
pero su proceso ya no existe). No hagas nada más salvo que te lo pidan.
