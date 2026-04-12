# Despliegue Nexus Brain

## Purpose

Red y secretos del compose para que el host alcance Ollama y servicios sensibles no queden expuestos sin decisión explícita.

## Requirements

| ID | Regla |
|----|--------|
| D1 | Si Ollama está en Docker y el cliente LLM en el host, **MUST** mapear `127.0.0.1:11434:11434` (o Ollama solo nativo sin contenedor duplicado). |
| D2 | Secretos (CouchDB, API keys) **MUST** estar en `.env` u otro secreto fuera de git; **MUST NOT** versionar valores reales. |
| D3 | Qdrant/Ollama **SHOULD** bind a `127.0.0.1` en el host salvo requisito documentado de acceso remoto. |
| D4 | GPU en Docker **MAY** usarse con reserva NVIDIA; sin GPU **SHOULD** alinearse con spec `openwebui-ollama` (modelo/timeout). |

### Requirement: D1 — Puerto Ollama hacia el host

#### Scenario: UI nativa, Ollama en Docker

- **GIVEN** OpenWebUI en host y `ollama` en Docker
- **WHEN** se llama `GET http://127.0.0.1:11434/api/tags` desde el host
- **THEN** la respuesta **MUST** ser HTTP exitosa (lista de modelos permitida vacía)

#### Scenario: Ollama solo nativo

- **GIVEN** sin servicio `ollama` en compose
- **WHEN** el operador configura la URL en la UI
- **THEN** la guía **MUST** indicar `http://localhost:11434` y ausencia de mapeo Docker

### Requirement: D2 — Secretos

#### Scenario: Arranque CouchDB

- **GIVEN** `COUCHDB_PASSWORD` en entorno
- **WHEN** el contenedor inicia
- **THEN** la contraseña **MUST NOT** quedar expuesta en logs persistentes de forma intencional

### Requirement: D3 — Qdrant local

#### Scenario: Acceso externo bloqueado por defecto

- **GIVEN** mapeo `127.0.0.1:6333:6333`
- **WHEN** un cliente remoto sin túnel intenta el puerto 6333
- **THEN** **MUST NOT** aceptarse conexión en la configuración documentada por defecto
