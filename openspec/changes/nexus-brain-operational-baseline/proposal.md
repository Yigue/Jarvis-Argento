# Propuesta: línea base operativa Nexus Brain (Jarvis-Argento)

## Intención

Dejar el stack **Obsidian + LiveSync + OpenWebUI/OpenClaw + Ollama + Qdrant + Caddy** en estado **verificable y estable** según `ARQUITECTURA_ANALISIS.md`: conectividad host↔contenedores, modelos acordes al hardware, RAG opcional y LiveSync funcional.

## Alcance

- **Incluye**: reglas de despliegue Docker (puertos, secretos, GPU opcional), integración OpenWebUI↔Ollama (URLs y timeouts), pipeline RAG (Knowledge Base + watcher), requisitos mínimos de CouchDB para LiveSync.
- **Excluye**: producto SaaS multi-tenant, Terraform/Ansible completos, código de aplicación Java del futuro Jarvis.

## Áreas afectadas

| Área | Artefactos típicos |
|------|---------------------|
| Despliegue | `docker-compose.yml`, `.env`, Caddyfile |
| Inferencia / UI | Configuración OpenWebUI, Ollama |
| RAG | Script watcher, API Knowledge, vector DB |
| Sincronización | CouchDB, plugin Obsidian |

## Enfoque

Corregir configuración puntual (fix, no “clean slate”): exponer Ollama al host cuando corre en Docker, ajustar GPU o Ollama nativo en CPU-only, elegir modelos ligeros primero, añadir RAG y LiveSync de forma incremental.

## Plan de rollback

- Restaurar versión anterior de `docker-compose` y Caddyfile desde control de versiones o backup.
- Deshabilitar `vault-watcher` (systemd) si introduce fallos.
- Revertir URL de Ollama y timeout en OpenWebUI a valores previos documentados.

## Riesgos

- Exponer puertos fuera de `127.0.0.1` aumenta superficie de ataque; MUST mantener Ollama/Qdrant en loopback salvo decisión explícita.
- Modelos grandes en CPU pueden seguir agotando timeouts aunque suba el límite; mitigación: modelo y hardware acordes.

## Criterios de éxito (alto nivel)

- Desde el host, `GET` a la API de etiquetas de Ollama responde éxito con el layout elegido (nativo o Docker con puerto publicado).
- OpenWebUI lista modelos y completa un turno de chat de prueba sin error de conexión.
- (Fase posterior) LiveSync sincroniza contra CouchDB con CORS correcto; (opcional) archivos `.md` del vault ingresan a la Knowledge Base configurada.
