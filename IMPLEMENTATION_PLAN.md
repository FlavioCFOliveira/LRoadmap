# Plano de Implementação - LRoadmap CLI

## Análise Exaustiva dos Requisitos

### 1. Visão Geral do Sistema

LRoadmap é uma CLI para gestão de roadmaps técnicos em workflows agentic, desenvolvida exclusivamente em Zig, com:
- **Output**: JSON exclusivo (sucessos e erros)
- **Input**: Apenas argumentos CLI (sem stdin, sem config files)
- **Storage**: SQLite em arquivos individuais (`~/.roadmaps/*.db`)
- **Datas**: ISO 8601 UTC (`2026-03-12T14:30:00.000Z`)

### 2. Estrutura de Dados

#### 2.1 Tabelas SQLite

**tasks** - Tarefas do roadmap
```sql
id INTEGER PRIMARY KEY AUTOINCREMENT
priority INTEGER (0-9, default 0)
severity INTEGER (0-9, default 0)
status TEXT (BACKLOG, SPRINT, DOING, TESTING, COMPLETED)
description TEXT NOT NULL
specialists TEXT (comma-separated)
action TEXT NOT NULL
expected_result TEXT NOT NULL
created_at TEXT ISO8601
completed_at TEXT ISO8601 (nullable)
```

**sprints** - Sprints ágeis
```sql
id INTEGER PRIMARY KEY AUTOINCREMENT
status TEXT (PENDING, OPEN, CLOSED)
description TEXT NOT NULL
created_at TEXT ISO8601
started_at TEXT ISO8601 (nullable)
closed_at TEXT ISO8601 (nullable)
```

**sprint_tasks** - Relacionamento N:M
```sql
sprint_id INTEGER FK
task_id INTEGER FK
added_at TEXT ISO8601
PRIMARY KEY (sprint_id, task_id)
```

**audit** - Log completo de operações
```sql
id INTEGER PRIMARY KEY AUTOINCREMENT
operation TEXT NOT NULL
entity_type TEXT (TASK, SPRINT)
entity_id INTEGER NOT NULL
performed_at TEXT ISO8601
```

**_metadata** - Metadados do roadmap
```sql
key TEXT PRIMARY KEY
value TEXT NOT NULL
```

#### 2.2 Enumerações

**TaskStatus**: `BACKLOG` → `SPRINT` → `DOING` → `TESTING` → `COMPLETED`
**SprintStatus**: `PENDING` → `OPEN` → `CLOSED`

### 3. Comandos por Categoria

#### 3.1 Global (2 comandos)
- `rmp --help` / `-h`
- `rmp --version` / `-v`

#### 3.2 Roadmap (4 comandos)
- `rmp roadmap list` / `ls` - Lista roadmaps
- `rmp roadmap create <name>` / `new` - Cria roadmap
- `rmp roadmap remove <name>` / `rm` / `delete` - Remove roadmap
- `rmp roadmap use <name>` - Define roadmap default

#### 3.3 Task (7 comandos)
- `rmp task list` / `ls` - Lista tasks
- `rmp task create` / `new` - Cria task
- `rmp task get <id>` - Obtém task(s)
- `rmp task set-status <id> <state>` / `stat` - Altera status
- `rmp task set-priority <id> <priority>` / `prio` - Altera prioridade
- `rmp task set-severity <id> <severity>` / `sev` - Altera severidade
- `rmp task remove <id>` / `rm` - Remove task

#### 3.4 Sprint (13 comandos)
- `rmp sprint list` / `ls` - Lista sprints
- `rmp sprint create` / `new` - Cria sprint
- `rmp sprint get <id>` - Obtém sprint
- `rmp sprint tasks <id>` - Lista tasks do sprint
- `rmp sprint add-tasks <sprint-id> <task-ids>` / `add` - Adiciona tasks
- `rmp sprint remove-tasks <sprint-id> <task-ids>` / `rm-tasks` - Remove tasks
- `rmp sprint move-tasks <from> <to> <task-ids>` / `mv-tasks` - Move tasks
- `rmp sprint update <id>` / `upd` - Atualiza descrição
- `rmp sprint start <id>` - Inicia sprint
- `rmp sprint close <id>` - Fecha sprint
- `rmp sprint reopen <id>` - Reabre sprint
- `rmp sprint stats <id>` - Estatísticas
- `rmp sprint remove <id>` / `rm` - Remove sprint

---

## Plano de Implementação - Status Atual

### Fase 1: Fundação ✅
- [x] Criar `build.zig` e `build.zig.zon`
- [x] Estruturar diretórios `src/`, `src/commands/`, `src/db/`, `src/models/`, `src/utils/`
- [x] `utils/time.zig`: `nowUtc()`, `formatTimestampSeconds()`, `isValidIso8601()`
- [x] `utils/path.zig`: `getRoadmapsDir()`, `getRoadmapPath()`, `ensureDirExists()`, `isValidRoadmapName()`, `listRoadmaps()`
- [x] `utils/json.zig`: `success()`, `errorResponse()`, `escapeString()`
- [x] Testes unitários para utilitários

### Fase 2: Modelos de Dados ✅
- [x] `models/task.zig`: Struct `Task`, Enum `TaskStatus`, `toJson()`
- [x] `models/sprint.zig`: Struct `Sprint`, Enum `SprintStatus`
- [x] `models/roadmap.zig`: Struct `Roadmap`
- [x] Testes unitários para modelos

### Fase 3: Camada de Database ✅
- [x] `db/connection.zig`: `open()`, `close()`, `exec()`, `beginTransaction()`, `commit()`, `rollback()`
- [x] `db/schema.zig`: DDL para todas as tabelas e `createSchema()`
- [x] `db/queries.zig`:
    - [x] `insertTask`, `updateTaskStatus`, `deleteTask`
    - [x] `insertSprint`, `updateSprintStatus`, `deleteSprint`
    - [x] `addTaskToSprint`, `removeTaskFromSprint`
    - [x] `logOperation`
    - [x] `listTasks` com filtros
    - [x] `getTasksByIds`
    - [x] `updateTaskPriority` / `updateTaskSeverity`
    - [x] `moveTaskBetweenSprints`
    - [x] `getSprintStats`

### Fase 4: Comandos Roadmap ✅
- [x] `roadmap list` (ls)
- [x] `roadmap create` (new)
- [x] `roadmap remove` (rm)
- [x] `roadmap use` (set default)

### Fase 5: Comandos Task ✅
- [x] `task list` (ls)
- [x] `task add` (new)
- [x] `task get`
- [x] `task status` (stat)
- [x] `task edit`
- [x] `task delete` (rm)
- [x] Suporte a múltiplos IDs (bulk operations: `1,2,3`) com output JSON único
- [x] Comandos específicos `prio` e `sev`

### Fase 6: Comandos Sprint ✅
- [x] `sprint list` (ls)
- [x] `sprint add` (new)
- [x] `sprint open` (start)
- [x] `sprint close`
- [x] `sprint add-task`
- [x] `sprint remove-task`
- [x] `sprint get`
- [x] `sprint tasks`
- [x] `sprint move-tasks` (mv-tasks)
- [x] `sprint update` (upd)
- [x] `sprint reopen`
- [x] `sprint stats`
- [x] `sprint remove` (rm)
- [x] Suporte a múltiplos IDs em operações de task e remove com output JSON único

### Fase 7: CLI Principal ✅
- [x] `src/main.zig`: Entry point
- [x] `src/cli.zig`: Argument parsing e routing
- [x] Global `--help` e `--version`
- [x] Suporte a roadmap default via `.current`

### Fase 8: Testes e Documentação ✅
- [x] Testes unitários na maioria dos módulos
- [x] Testes de integração end-to-end (`tests/integration_test.sh`)
- [x] Documentação completa no README.md (atualizado)

### Fase 9: Refinamento e Conformidade Estrita ✅
- [x] Padronizar nomes de operações no log de auditoria conforme `SPEC/DATA_FORMATS.md`
- [x] Adicionar validações de range (0-9) na camada CLI com erros específicos
- [x] Expandir JSON de `help` para incluir `options`, `required` e `examples`
- [x] Implementar campo `details` em respostas de erro críticas (ex: IDs inexistentes)

---

## Próximos Passos

1. **Refinamento**: Executar a Fase 9 para garantir conformidade total com as especificações técnicas.

---

## Resumo do Cronograma Finalizado

| Fase | Componentes | Status |
|------|-------------|--------|
| 1 | Setup + Utils | ✅ Concluído |
| 2 | Models | ✅ Concluído |
| 3 | Database Layer | ✅ Concluído |
| 4 | Roadmap Commands | ✅ Concluído |
| 5 | Task Commands | ✅ Concluído |
| 6 | Sprint Commands | ✅ Concluído |
| 7 | Main + CLI | ✅ Concluído |
| 8 | Testes + Docs | ✅ Concluído |
| 9 | Refinamento | ✅ Concluído |

**Progresso Total Estimado**: 100% do projeto concluído.
