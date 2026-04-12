# Vault, RAG y LiveSync

## Purpose

LiveSync con CouchDB, ingesta del vault a Knowledge Base y política de vector DB, sin detalle de implementación interna de OpenWebUI.

## Requirements

| ID | Regla |
|----|--------|
| V1 | **MUST** existir forma de crear/asociar una Knowledge Base al vault; su id **MUST** ser usable por automatización. |
| V2 | Watcher (si existe) **MUST** ignorar `.obsidian` y procesar `.md`; **MUST** registrar éxito/error HTTP por archivo. |
| V3 | **MAY** usar vector DB integrada al inicio; **SHOULD** poder migrar a Qdrant vía env documentado; misma KB salvo reindexación explícita. |
| V4 | CouchDB para LiveSync **MUST** tener CORS/credenciales según plugin; DB **MUST** existir antes de clientes. |
| V5 | Frontmatter en notas **SHOULD** usarse para mejor retrieval; **MAY** omitirse en arranque mínimo. |

### Requirement: V1 — Knowledge Base

#### Scenario: API y chat

- **GIVEN** KB creada
- **WHEN** se anota el id y se indexa un `.md`
- **THEN** con KB adjunta en el hilo, la respuesta **SHOULD** usar RAG cuando aplique

### Requirement: V2 — Watcher

#### Scenario: Cambio en vault

- **GIVEN** watcher activo, `KNOWLEDGE_ID` válido
- **WHEN** `close_write` en `.md` fuera de `.obsidian`
- **THEN** ingesta **MUST** intentarse y el log **MUST** indicar resultado

### Requirement: V3 — Qdrant

#### Scenario: Migración

- **GIVEN** Qdrant en `127.0.0.1:6333` y env `VECTOR_DB` apuntando a Qdrant
- **WHEN** se completa migración/reindex según guía
- **THEN** consulta RAG **MUST** seguir operativa para esa KB

### Requirement: V4 — LiveSync

#### Scenario: Obsidian conecta

- **GIVEN** HTTPS a CouchDB vía proxy y DB creada
- **WHEN** plugin con credenciales de entorno
- **THEN** al menos un ciclo push/pull de prueba **MUST** completar sin error CORS

### Requirement: V5 — Frontmatter

#### Scenario: Nota estructurada

- **GIVEN** nota con frontmatter consistente
- **WHEN** se indexa
- **THEN** recuperación por tema **SHOULD** superar a nota sin metadatos en el mismo escenario de búsqueda
