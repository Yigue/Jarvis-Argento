# Skill registry — Jarvis-Argento

Generado en la inicialización SDD. Skills de usuario (deduplicados por nombre; gana el del proyecto si existiera).

## Convenciones del proyecto

| Archivo | Presente |
|---------|----------|
| agents.md / AGENTS.md | No |
| .cursorrules | No |
| CLAUDE.md (raíz) | No |

## Skills instalados (usuario)

| Nombre | Ruta | Disparadores (resumen) |
|--------|------|-------------------------|
| go-testing | `~/.claude/skills/go-testing` | Tests Go, Gentleman.Dots, Bubbletea, teatest |
| sdd-apply | `~/.claude/skills/sdd-apply` | Implementar tareas de un change |
| sdd-archive | `~/.claude/skills/sdd-archive` | Archivar change, sincronizar specs |
| sdd-design | `~/.claude/skills/sdd-design` | Diseño técnico del change |
| sdd-explore | `~/.claude/skills/sdd-explore` | Exploración antes de comprometer change |
| sdd-init | `~/.claude/skills/sdd-init` | Inicializar SDD / openspec |
| sdd-propose | `~/.claude/skills/sdd-propose` | Propuesta de change |
| sdd-spec | `~/.claude/skills/sdd-spec` | Especificaciones delta |
| sdd-tasks | `~/.claude/skills/sdd-tasks` | Desglose de tareas |
| sdd-verify | `~/.claude/skills/sdd-verify` | Verificación vs specs |
| skill-creator | `~/.claude/skills/skill-creator` | Crear nuevas skills |
| skill-registry | `~/.claude/skills/skill-registry` | Registro de skills del proyecto |

## Skills Cursor (usuario)

| Nombre | Ruta |
|--------|------|
| babysit | `~/.cursor/skills-cursor/babysit` |
| create-hook | `~/.cursor/skills-cursor/create-hook` |
| create-rule | `~/.cursor/skills-cursor/create-rule` |
| create-skill | `~/.cursor/skills-cursor/create-skill` |
| create-subagent | `~/.cursor/skills-cursor/create-subagent` |
| migrate-to-skills | `~/.cursor/skills-cursor/migrate-to-skills` |
| shell | `~/.cursor/skills-cursor/shell` |
| statusline | `~/.cursor/skills-cursor/statusline` |
| update-cli-config | `~/.cursor/skills-cursor/update-cli-config` |
| update-cursor-settings | `~/.cursor/skills-cursor/update-cursor-settings` |

## Notas

- Skills `sdd-*` y `_shared` se omiten del escaneo recursivo adicional según convención sdd-init; aquí se listan explícitamente las sdd encontradas en `~/.claude/skills/`.
- Reglas de arquitectura Java (MVC/GRASP) del usuario aplican a código Java; este repo es principalmente documentación e infraestructura descrita en markdown.
