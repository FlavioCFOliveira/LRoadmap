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

### 4. Análise de Dependências

```
┌─────────────────────────────────────────────────────────────────┐
│                    GRÁFICO DE DEPENDÊNCIAS                      │
└─────────────────────────────────────────────────────────────────┘

Nível 0 - Infraestrutura (Sem dependências)
├── utils/json.zig
├── utils/time.zig
└── utils/path.zig

Nível 1 - Modelos (Sem dependências)
├── models/task.zig
├── models/sprint.zig
└── models/roadmap.zig

Nível 2 - Database (Depende de Nível 0 e 1)
├── db/connection.zig
├── db/schema.zig
└── db/queries.zig

Nível 3 - Comandos Roadmap (Depende de Nível 2)
└── commands/roadmap.zig
    ├── roadmap list
    ├── roadmap create
    ├── roadmap remove
    └── roadmap use

Nível 4 - Comandos Task (Depende de Nível 3)
└── commands/task.zig
    ├── task list
    ├── task create
    ├── task get
    ├── task set-status
    ├── task set-priority
    ├── task set-severity
    └── task remove

Nível 5 - Comandos Sprint (Depende de Nível 4)
└── commands/sprint.zig
    ├── sprint list
    ├── sprint create
    ├── sprint get
    ├── sprint tasks
    ├── sprint add-tasks
    ├── sprint remove-tasks
    ├── sprint move-tasks
    ├── sprint update
    ├── sprint start
    ├── sprint close
    ├── sprint reopen
    ├── sprint stats
    └── sprint remove

Nível 6 - Entry Point (Depende de todos)
└── main.zig
    ├── CLI parsing
    ├── Command routing
    └── Error handling
```

---

## Plano de Implementação

### Fase 1: Fundação (Semanas 1-2)

#### Tarefa 1.1: Setup do Projeto
**Complexidade**: Baixa | **Dependências**: Nenhuma
- [ ] Criar `build.zig` com configurações básicas
- [ ] Criar `build.zig.zon` (package manifest)
- [ ] Estruturar diretórios `src/`, `src/commands/`, `src/db/`, `src/models/`, `src/utils/`
- [ ] Configurar integração com SQLite (zig-sqlite ou bindings C)

**Arquivos criados**:
- `build.zig`
- `build.zig.zon`
- Estrutura de diretórios

#### Tarefa 1.2: Utilitários Core
**Complexidade**: Baixa | **Dependências**: Nenhuma

##### 1.2.1: utils/time.zig
- [ ] Função `nowUtc()` → retorna ISO 8601 string UTC
- [ ] Função `formatIso8601(timestamp)` → formatação consistente
- [ ] Função `parseIso8601(string)` → parsing de datas

##### 1.2.2: utils/path.zig
- [ ] Função `getRoadmapsDir()` → retorna `~/.roadmaps/`
- [ ] Função `getRoadmapPath(name)` → retorna caminho completo
- [ ] Função `ensureDirExists(path)` → cria diretório se não existir
- [ ] Suporte cross-platform (Linux, macOS, Windows)

##### 1.2.3: utils/json.zig
- [ ] Função `successResponse(data)` → JSON de sucesso
- [ ] Função `errorResponse(code, message, details)` → JSON de erro
- [ ] Função `serializeTask(task)` → JSON da task
- [ ] Função `serializeSprint(sprint)` → JSON do sprint
- [ ] Função `serializeRoadmap(roadmap)` → JSON do roadmap

**Arquivos criados**:
- `src/utils/time.zig`
- `src/utils/path.zig`
- `src/utils/json.zig`

**Testes**:
- [ ] Testes unitários para time.zig
- [ ] Testes unitários para path.zig
- [ ] Testes unitários para json.zig

---

### Fase 2: Modelos de Dados (Semana 2)

#### Tarefa 2.1: Modelos Core
**Complexidade**: Baixa | **Dependências**: Nível 1 completo

##### 2.1.1: models/task.zig
```zig
pub const TaskStatus = enum {
    BACKLOG,
    SPRINT,
    DOING,
    TESTING,
    COMPLETED,
};

pub const Task = struct {
    id: i64,
    priority: i32,        // 0-9
    severity: i32,        // 0-9
    status: TaskStatus,
    description: []const u8,
    specialists: ?[]const u8,
    action: []const u8,
    expected_result: []const u8,
    created_at: []const u8,     // ISO 8601
    completed_at: ?[]const u8, // ISO 8601
};
```
- [ ] Definir struct `Task`
- [ ] Definir enum `TaskStatus`
- [ ] Implementar métodos de serialização/deserialização

##### 2.1.2: models/sprint.zig
```zig
pub const SprintStatus = enum {
    PENDING,
    OPEN,
    CLOSED,
};

pub const Sprint = struct {
    id: i64,
    status: SprintStatus,
    description: []const u8,
    tasks: []i64,        // Array de task IDs
    task_count: i32,
    created_at: []const u8,
    started_at: ?[]const u8,
    closed_at: ?[]const u8,
};
```
- [ ] Definir struct `Sprint`
- [ ] Definir enum `SprintStatus`
- [ ] Implementar métodos de serialização

##### 2.1.3: models/roadmap.zig
```zig
pub const Roadmap = struct {
    name: []const u8,
    path: []const u8,
    size: i64,
    created_at: []const u8,
};
```
- [ ] Definir struct `Roadmap`
- [ ] Implementar métodos auxiliares

**Arquivos criados**:
- `src/models/task.zig`
- `src/models/sprint.zig`
- `src/models/roadmap.zig`

---

### Fase 3: Camada de Database (Semanas 3-4)

#### Tarefa 3.1: Conexão e Schema
**Complexidade**: Média | **Dependências**: Nível 2

##### 3.1.1: db/connection.zig
- [ ] Função `open(name)` → abre conexão SQLite
- [ ] Função `close(conn)` → fecha conexão
- [ ] Função `isValidRoadmap(path)` → verifica magic bytes SQLite
- [ ] Gerenciamento de pool de conexões (se necessário)

##### 3.1.2: db/schema.zig
- [ ] DDL para tabela `tasks`
- [ ] DDL para tabela `sprints`
- [ ] DDL para tabela `sprint_tasks`
- [ ] DDL para tabela `audit`
- [ ] DDL para tabela `_metadata`
- [ ] Índices: `idx_tasks_status`, `idx_tasks_priority`, etc.
- [ ] Função `createSchema(conn)` → cria todas as tabelas

**Arquivos criados**:
- `src/db/connection.zig`
- `src/db/schema.zig`

#### Tarefa 3.2: Queries Parametrizadas
**Complexidade**: Média | **Dependências**: 3.1

##### 3.2.1: db/queries.zig - Tasks
- [ ] `insertTask(conn, task)` → INSERT com prepared statement
- [ ] `listTasks(conn, filters)` → SELECT com filtros opcionais
- [ ] `getTaskById(conn, id)` → SELECT by ID
- [ ] `getTasksByIds(conn, ids)` → SELECT múltiplos IDs
- [ ] `updateTaskStatus(conn, ids, status)` → UPDATE status
- [ ] `updateTaskPriority(conn, ids, priority)` → UPDATE priority
- [ ] `updateTaskSeverity(conn, ids, severity)` → UPDATE severity
- [ ] `deleteTask(conn, id)` → DELETE

##### 3.2.2: db/queries.zig - Sprints
- [ ] `insertSprint(conn, sprint)` → INSERT
- [ ] `listSprints(conn, filters)` → SELECT
- [ ] `getSprintById(conn, id)` → SELECT by ID
- [ ] `updateSprintStatus(conn, id, status)` → UPDATE status
- [ ] `updateSprintDescription(conn, id, description)` → UPDATE
- [ ] `deleteSprint(conn, id)` → DELETE

##### 3.2.3: db/queries.zig - Sprint Tasks
- [ ] `addTaskToSprint(conn, sprintId, taskId)` → INSERT
- [ ] `removeTaskFromSprint(conn, taskId)` → DELETE
- [ ] `getTasksBySprint(conn, sprintId)` → SELECT com JOIN
- [ ] `moveTaskBetweenSprints(conn, taskId, fromId, toId)` → UPDATE
- [ ] `getSprintStats(conn, sprintId)` → SELECT com COUNT/GROUP BY

##### 3.2.4: db/queries.zig - Audit
- [ ] `logOperation(conn, operation, entityType, entityId)` → INSERT
- [ ] `getAuditHistory(conn, entityType, entityId)` → SELECT

**Arquivos criados**:
- `src/db/queries.zig`

**Testes**:
- [ ] Testes de integração com banco em memória
- [ ] Testes de CRUD para cada entidade
- [ ] Testes de transações

---

### Fase 4: Comandos Roadmap (Semana 5)

#### Tarefa 4.1: Implementação Roadmap Commands
**Complexidade**: Média | **Dependências**: Nível 3 completo

##### 4.1.1: commands/roadmap.zig - list
- [ ] Comando `rmp roadmap list` / `rmp road ls`
- [ ] Listar arquivos `.db` em `~/.roadmaps/`
- [ ] Ler metadados de cada arquivo
- [ ] Output JSON: `{ success: true, data: { count, roadmaps[] } }`

##### 4.1.2: commands/roadmap.zig - create
- [ ] Comando `rmp roadmap create <name>` / `new`
- [ ] Validar nome (alphanumeric, hyphen, underscore, max 50)
- [ ] Verificar se já existe
- [ ] Opção `--force` para sobrescrever
- [ ] Criar diretório `~/.roadmaps/` se não existir
- [ ] Criar arquivo SQLite com schema
- [ ] Inserir metadados iniciais
- [ ] Output JSON com `name`, `path`, `created_at`

##### 4.1.3: commands/roadmap.zig - remove
- [ ] Comando `rmp roadmap remove <name>` / `rm` / `delete`
- [ ] Validar se é arquivo SQLite válido antes de remover
- [ ] Remover arquivo `.db`
- [ ] Output JSON com `name`, `removed_at`

##### 4.1.4: commands/roadmap.zig - use
- [ ] Comando `rmp roadmap use <name>`
- [ ] Armazenar roadmap default em arquivo oculto (`.current_roadmap`)
- [ ] Output JSON de confirmação

**Arquivos criados**:
- `src/commands/roadmap.zig`

**Testes**:
- [ ] Testes de criação de roadmap
- [ ] Testes de listagem
- [ ] Testes de remoção
- [ ] Testes de validação de nome

---

### Fase 5: Comandos Task (Semanas 6-7)

#### Tarefa 5.1: Implementação Task Commands
**Complexidade**: Média-Alta | **Dependências**: Nível 4

##### 5.1.1: commands/task.zig - list
- [ ] Comando `rmp task list -r <name>` / `ls`
- [ ] Filtros: `--status`, `--priority` (min), `--limit`
- [ ] Ordenação por prioridade DESC, created_at ASC
- [ ] Output JSON com array de tasks

##### 5.1.2: commands/task.zig - create
- [ ] Comando `rmp task create -r <name> -d <desc> -a <action> -e <result>`
- [ ] Parâmetros obrigatórios: roadmap, description, action, expected_result
- [ ] Parâmetros opcionais: priority (0-9), severity (0-9), specialists
- [ ] Validar range de priority/severity
- [ ] Inserir task + log audit
- [ ] Output JSON com task criada (incluindo ID gerado)

##### 5.1.3: commands/task.zig - get
- [ ] Comando `rmp task get -r <name> <id>`
- [ ] Suporte a múltiplos IDs: `1,2,3`
- [ ] Verificar existência de cada ID
- [ ] Erro parcial se alguns IDs não existirem
- [ ] Output JSON com task(s)

##### 5.1.4: commands/task.zig - set-status (stat)
- [ ] Comando `rmp task stat -r <name> <id> <state>`
- [ ] Suporte bulk: `rmp task stat -r name 1,2,3 DOING`
- [ ] Estados válidos: BACKLOG, SPRINT, DOING, TESTING, COMPLETED
- [ ] Se COMPLETED, atualizar `completed_at`
- [ ] Log audit para cada task atualizada
- [ ] Output JSON com `updated`, `count`, `new_status`

##### 5.1.5: commands/task.zig - set-priority (prio)
- [ ] Comando `rmp task prio -r <name> <id> <priority>`
- [ ] Suporte bulk
- [ ] Validar range 0-9
- [ ] Log audit
- [ ] Output JSON

##### 5.1.6: commands/task.zig - set-severity (sev)
- [ ] Comando `rmp task sev -r <name> <id> <severity>`
- [ ] Suporte bulk
- [ ] Validar range 0-9
- [ ] Log audit
- [ ] Output JSON

##### 5.1.7: commands/task.zig - remove
- [ ] Comando `rmp task rm -r <name> <id>`
- [ ] Suporte bulk
- [ ] Remover de sprint_tasks se existir (CASCADE)
- [ ] Log audit
- [ ] Output JSON

**Arquivos criados**:
- `src/commands/task.zig`

**Testes**:
- [ ] Testes de CRUD de tasks
- [ ] Testes de filtros
- [ ] Testes de bulk operations
- [ ] Testes de validação de status/priority/severity

---

### Fase 6: Comandos Sprint (Semanas 8-10)

#### Tarefa 6.1: Implementação Sprint Commands
**Complexidade**: Alta | **Dependências**: Nível 5

##### 6.1.1: commands/sprint.zig - list
- [ ] Comando `rmp sprint list -r <name>` / `ls`
- [ ] Filtro: `--status`
- [ ] Output JSON com sprints

##### 6.1.2: commands/sprint.zig - create
- [ ] Comando `rmp sprint create -r <name> -d <description>`
- [ ] Criar sprint com status PENDING
- [ ] Log audit
- [ ] Output JSON

##### 6.1.3: commands/sprint.zig - get
- [ ] Comando `rmp sprint get -r <name> <id>`
- [ ] Incluir array de task IDs
- [ ] Output JSON

##### 6.1.4: commands/sprint.zig - tasks
- [ ] Comando `rmp sprint tasks -r <name> <id>`
- [ ] Filtro por status
- [ ] Output JSON com tasks

##### 6.1.5: commands/sprint.zig - add-tasks
- [ ] Comando `rmp sprint add -r <name> <sprint-id> <task-ids>`
- [ ] Verificar se tasks existem
- [ ] Verificar se tasks já estão em outro sprint
- [ ] Inserir em sprint_tasks
- [ ] Atualizar status das tasks para SPRINT
- [ ] Log audit para cada task
- [ ] Output JSON

##### 6.1.6: commands/sprint.zig - remove-tasks
- [ ] Comando `rmp sprint rm-tasks -r <name> <sprint-id> <task-ids>`
- [ ] Remover de sprint_tasks
- [ ] Atualizar status das tasks para BACKLOG
- [ ] Log audit
- [ ] Output JSON

##### 6.1.7: commands/sprint.zig - move-tasks
- [ ] Comando `rmp sprint mv-tasks -r <name> <from> <to> <task-ids>`
- [ ] Atualizar sprint_tasks (mudar sprint_id)
- [ ] Manter status SPRINT
- [ ] Log audit
- [ ] Output JSON

##### 6.1.8: commands/sprint.zig - update
- [ ] Comando `rmp sprint upd -r <name> <id> -d <description>`
- [ ] Atualizar descrição
- [ ] Log audit
- [ ] Output JSON

##### 6.1.9: commands/sprint.zig - start
- [ ] Comando `rmp sprint start -r <name> <id>`
- [ ] Status PENDING → OPEN
- [ ] Definir started_at
- [ ] Log audit
- [ ] Output JSON

##### 6.1.10: commands/sprint.zig - close
- [ ] Comando `rmp sprint close -r <name> <id>`
- [ ] Status OPEN → CLOSED
- [ ] Definir closed_at
- [ ] Log audit
- [ ] Output JSON

##### 6.1.11: commands/sprint.zig - reopen
- [ ] Comando `rmp sprint reopen -r <name> <id>`
- [ ] Status CLOSED → OPEN
- [ ] Limpar closed_at
- [ ] Log audit
- [ ] Output JSON

##### 6.1.12: commands/sprint.zig - stats
- [ ] Comando `rmp sprint stats -r <name> <id>`
- [ ] Calcular: total_tasks, by_status{}, completion_percentage
- [ ] Output JSON detalhado

##### 6.1.13: commands/sprint.zig - remove
- [ ] Comando `rmp sprint rm -r <name> <id>`
- [ ] Antes de remover: atualizar tasks para BACKLOG
- [ ] Remover sprint_tasks (CASCADE)
- [ ] Remover sprint
- [ ] Log audit
- [ ] Output JSON

**Arquivos criados**:
- `src/commands/sprint.zig`

**Testes**:
- [ ] Testes de ciclo de vida de sprint
- [ ] Testes de adição/remoção de tasks
- [ ] Testes de estatísticas
- [ ] Testes de transições de status

---

### Fase 7: CLI Principal (Semana 11)

#### Tarefa 7.1: Main e Routing
**Complexidade**: Média | **Dependências**: Todas as fases anteriores

##### 7.1.1: src/main.zig
- [ ] Parse de argumentos CLI
- [ ] Estrutura: `rmp [command] [subcommand] [args] [options]`
- [ ] Router para commands/roadmap.zig
- [ ] Router para commands/task.zig
- [ ] Router para commands/sprint.zig
- [ ] Handler global `--help`
- [ ] Handler global `--version`
- [ ] Leitura de roadmap default (de `.current_roadmap`)
- [ ] Tratamento de erros global
- [ ] Sempre output JSON (mesmo para erros de parsing)

##### 7.1.2: Validação de Argumentos
- [ ] Validar comando/subcomando existe
- [ ] Validar argumentos obrigatórios
- [ ] Validar formato de flags
- [ ] Mensagens de erro em JSON

**Arquivos modificados**:
- `src/main.zig`

---

### Fase 8: Testes e Documentação (Semana 12)

#### Tarefa 8.1: Testes Finais
**Complexidade**: Média | **Dependências**: Fase 7

- [ ] Testes de integração end-to-end
- [ ] Testes de casos de borda
- [ ] Testes de concorrência (se aplicável)
- [ ] Testes de performance
- [ ] Cobertura de código > 80%

#### Tarefa 8.2: Documentação
**Complexidade**: Baixa | **Dependências**: Testes

- [ ] Atualizar README.md com instruções de instalação
- [ ] Documentar exemplos de uso
- [ ] Documentar fluxos de trabalho típicos
- [ ] Changelog

---

## Resumo do Cronograma

| Fase | Semana(s) | Componentes | Status |
|------|-----------|-------------|--------|
| 1 | 1-2 | Setup + Utils | ⏳ Pendente |
| 2 | 2 | Models | ⏳ Pendente |
| 3 | 3-4 | Database Layer | ⏳ Pendente |
| 4 | 5 | Roadmap Commands | ⏳ Pendente |
| 5 | 6-7 | Task Commands | ⏳ Pendente |
| 6 | 8-10 | Sprint Commands | ⏳ Pendente |
| 7 | 11 | Main + CLI | ⏳ Pendente |
| 8 | 12 | Testes + Docs | ⏳ Pendente |

**Total estimado**: 12 semanas (3 meses) para 1 desenvolvedor full-time

---

## Checklist de Funcionalidades

### Infraestrutura
- [ ] Build system configurado
- [ ] Test framework configurado
- [ ] SQLite integrado
- [ ] Utils (JSON, Time, Path) implementados e testados

### Modelos
- [ ] Task model
- [ ] Sprint model
- [ ] Roadmap model
- [ ] Enums definidos

### Database
- [ ] Conexão SQLite
- [ ] Schema creation
- [ ] Queries de Task
- [ ] Queries de Sprint
- [ ] Queries de Sprint_Task
- [ ] Queries de Audit

### Roadmap Commands
- [ ] roadmap list
- [ ] roadmap create
- [ ] roadmap remove
- [ ] roadmap use

### Task Commands
- [ ] task list
- [ ] task create
- [ ] task get
- [ ] task set-status (stat)
- [ ] task set-priority (prio)
- [ ] task set-severity (sev)
- [ ] task remove

### Sprint Commands
- [ ] sprint list
- [ ] sprint create
- [ ] sprint get
- [ ] sprint tasks
- [ ] sprint add-tasks
- [ ] sprint remove-tasks
- [ ] sprint move-tasks
- [ ] sprint update
- [ ] sprint start
- [ ] sprint close
- [ ] sprint reopen
- [ ] sprint stats
- [ ] sprint remove

### CLI Principal
- [ ] Argument parsing
- [ ] Command routing
- [ ] Global --help
- [ ] Global --version
- [ ] Error handling
- [ ] Default roadmap support

---

## Notas de Implementação

### Prioridade vs Severidade
- **Priority** (0-9): Urgência/Pertinência (Product Owner)
- **Severity** (0-9): Impacto Técnico (Dev Team)
- Podem ser independentes: um bug crítico pode ter severity=9 mas priority=3

### Transições de Status

**Task**:
```
BACKLOG ↔ SPRINT ↔ DOING ↔ TESTING ↔ COMPLETED
```
- Quando COMPLETED: definir completed_at

**Sprint**:
```
PENDING → OPEN → CLOSED
         ↑______|
```
- PENDING → OPEN: definir started_at
- OPEN → CLOSED: definir closed_at
- CLOSED → OPEN: limpar closed_at (reopen)

### Regras de Negócio Importantes

1. **Uma task pode estar em apenas um sprint por vez** (constraint UNIQUE na sprint_tasks)
2. **Remover sprint**: tasks associadas voltam para BACKLOG
3. **Adicionar task a sprint**: status muda automaticamente para SPRINT
4. **Remover task de sprint**: status volta para BACKLOG
5. **Mover task entre sprints**: status mantém SPRINT

### Audit Log
Toda operação que altera estado deve ser logada:
- Criação/deleção de tasks/sprints
- Mudanças de status
- Mudanças de priority/severity
- Associação/desassociação de tasks a sprints

### JSON Output
Sempre estruturado como:
```json
{
  "success": true|false,
  "data": { ... },           // se success=true
  "error": {                 // se success=false
    "code": "...",
    "message": "...",
    "details": { ... }
  }
}
```

### Formato de IDs Múltiplos
Comma-separated, sem espaços: `1,2,3,10,15`

### Validações
- Nome do roadmap: alphanumeric + hyphen + underscore, max 50 chars
- Priority: 0-9
- Severity: 0-9
- Status: valores do enum apenas
