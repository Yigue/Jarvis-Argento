# OpenWebUI ↔ Ollama

## Purpose

Conectividad y parámetros de inferencia según topología y hardware.

## Requirements

| ID | Regla |
|----|--------|
| O1 | URL de Ollama **MUST** coincidir con topología: `localhost` (ambos nativos), `host.docker.internal` (UI en Docker, Ollama en host), o nombre de servicio en red compose compartida. |
| O2 | Sin GPU o modelos pesados en CPU: timeout de petición en OpenWebUI **SHOULD** aumentarse para evitar fallos falsos. |
| O3 | Guía operativa **MUST NOT** imponer un único modelo inviable en VPS sin GPU; **SHOULD** proponer modelo ligero inicial. |
| O4 | Post-cambio de red, **MUST** existir verificación documentada vía `curl` a `/api/tags` desde el mismo contexto que la UI. |

### Requirement: O1 — URL correcta

#### Scenario: Nativo + Docker publicado

- **GIVEN** Ollama en Docker con `127.0.0.1:11434` y UI en host
- **WHEN** se guarda la conexión en OpenWebUI
- **THEN** los modelos **MUST** listarse sin error de red tras refresco

#### Scenario: UI en Docker

- **GIVEN** URL `http://host.docker.internal:11434`
- **WHEN** el contenedor OpenWebUI resuelve el endpoint
- **THEN** `/api/tags` **MUST** responder éxito

### Requirement: O2 — Timeout CPU

#### Scenario: Generación lenta válida

- **GIVEN** timeout elevado según guía
- **WHEN** mensaje de prueba corto
- **THEN** **MUST** llegar respuesta o error explícito de modelo/servidor, no solo timeout por límite por defecto inadecuado

### Requirement: O3 — Modelo inicial

#### Scenario: VPS sin GPU

- **GIVEN** sin GPU
- **WHEN** se sigue la guía de modelo inicial
- **THEN** al menos un modelo ligero **MUST** completar prueba CLI y desde OpenWebUI
