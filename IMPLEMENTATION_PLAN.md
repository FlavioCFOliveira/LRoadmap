# Plano de Implementação - LRoadmap CLI

## Status Atual (2026-03-13)

### Funcionalidades Implementadas ✅

#### Roadmap Management (100%)
| Comando | Status | Ficheiro |
|---------|--------|----------|
| `rmp roadmap list` / `ls` | ✅ Implementado | `src/commands/roadmap.zig` |
| `rmp roadmap create` / `new` | ✅ Implementado | `src/commands/roadmap.zig` |
| `rmp roadmap remove` / `rm` | ✅ Implementado | `src/commands/roadmap.zig` |
| `rmp roadmap use` | ✅ Implementado | `src/commands/roadmap.zig` |

#### Task Management (100%)
| Comando | Status | Ficheiro |
|---------|--------|----------|
| `rmp task list` / `ls` | ✅ Implementado (com filtro de status) | `src/commands/task.zig` |
| `rmp task get <ids>` | ✅ Implementado (bulk suportado) | `src/commands/task.zig` |
| `rmp task add` / `new` | ✅ Implementado | `src/commands/task.zig` |
| `rmp task status` / `stat` | ✅ Implementado (bulk suportado) | `src/commands/task.zig` |
| `rmp task prio` | ✅ Implementado (bulk suportado) | `src/commands/task.zig` |
| `rmp task sev` | ✅ Implementado (bulk suportado) | `src/commands/task.zig` |
| `rmp task edit` | ✅ Implementado | `src/commands/task.zig` |
| `rmp task delete` / `rm` | ✅ Implementado (bulk suportado) | `src/commands/task.zig` |

#### Sprint Management (100%)
| Comando | Status | Ficheiro |
|---------|--------|----------|
| `rmp sprint list` / `ls` | ✅ Implementado (com filtro de status) | `src/commands/sprint.zig` |
| `rmp sprint get <id>` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint tasks <id>` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint add` / `new` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint open` / `start` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint close` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint reopen` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint stats` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint update` / `upd` | ✅ Implementado | `src/commands/sprint.zig` |
| `rmp sprint add-task` | ✅ Implementado (bulk suportado) | `src/commands/sprint.zig` |
| `rmp sprint remove-task` / `rm-tasks` | ✅ Implementado (bulk suportado) | `src/commands/sprint.zig` |
| `rmp sprint move-tasks` / `mv-tasks` | ✅ Implementado (bulk suportado) | `src/commands/sprint.zig` |
| `rmp sprint remove` / `rm` | ✅ Implementado (bulk suportado) | `src/commands/sprint.zig` |

---

## Funcionalidades Pendentes ⏳

### 1. Audit Log Management (Alta Prioridade)

**Local na SPEC:** `SPEC/COMMANDS.md` (linhas 529-720) e `SPEC/COMMANDS_REFERENCE.md` (linhas 245-287)

> **Nota:** A tabela `audit` já existe no schema (`src/db/schema.zig`) e as operações são logadas via `queries.logOperation()`. O que falta é a **interface CLI** para consultar estes logs.

#### 1.1 List Audit Entries ✅
```bash
# Comandos especificados na SPEC:
rmp audit list --roadmap <name>
rmp audit ls -r <name>

# Com filtros:
rmp audit list -r <name> --operation TASK_STATUS_CHANGE
rmp audit list -r <name> -o SPRINT_START
rmp audit list -r <name> --entity-type TASK
rmp audit list -r <name> -e SPRINT
rmp audit list -r <name> --entity-id 42
rmp audit list -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit list -r <name> --until 2026-03-12T23:59:59.000Z
rmp audit list -r <name> --limit 50
```

**Opções:**
- `-r, --roadmap <name>`: Roadmap (obrigatório)
- `-o, --operation <type>`: Filtrar por tipo de operação
- `-e, --entity-type <type>`: Filtrar por tipo de entidade (TASK, SPRINT)
- `--entity-id <id>`: Filtrar por ID de entidade específica
- `--since <date>`: Incluir entradas a partir desta data (ISO 8601)
- `--until <date>`: Incluir entradas até esta data (ISO 8601)
- `-l, --limit <n>`: Limitar resultados (default: 100, max: 1000)
- `--offset <n>`: Offset para paginação (default: 0)

**JSON Output esperado:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "count": 3,
    "total": 150,
    "filters": { "operation": null, "entity_type": null, ... },
    "entries": [
      { "id": 152, "operation": "TASK_STATUS_CHANGE", "entity_type": "TASK", "entity_id": 42, "performed_at": "2026-03-13T10:30:00.000Z" },
      ...
    ]
  }
}
```

**Tarefas:**
- [x] Criar `src/commands/audit.zig` com estrutura base
- [x] Implementar `listAuditEntries()`
- [x] Adicionar queries de filtro em `src/db/queries.zig`:
  - [x] `listAuditEntries()` - base query com filtros
- [x] Adicionar handler em `src/cli.zig` para comando `audit`
- [x] Adicionar filtros: operation, entity-type, entity-id, since, until, limit, offset

#### 1.2 Get Entity History ✅
```bash
rmp audit history --roadmap <name> --entity-type TASK <id>
rmp audit hist -r <name> -e TASK 42

rmp audit history -r <name> --entity-type SPRINT <id>
rmp audit hist -r <name> -e SPRINT 1
```

**Argumentos:**
- `id`: ID da entidade (obrigatório)

**Opções:**
- `-r, --roadmap <name>`: Roadmap (obrigatório)
- `-e, --entity-type <type>`: Tipo de entidade (TASK, SPRINT) - obrigatório

**Tarefas:**
- [x] Implementar `getEntityHistory()` em `src/commands/audit.zig`
- [x] Adicionar query `getEntityHistory()` em `src/db/queries.zig`

#### 1.3 Audit Statistics ✅
```bash
rmp audit stats --roadmap <name>
rmp audit stats -r <name>

# Estatísticas para período específico:
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z --until 2026-03-31T23:59:59.000Z
```

**JSON Output esperado:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "period": { "since": "...", "until": "..." },
    "total_entries": 150,
    "by_operation": { "TASK_CREATE": 25, "TASK_STATUS_CHANGE": 45, ... },
    "by_entity_type": { "TASK": 93, "SPRINT": 57 },
    "first_entry": "2026-03-01T09:00:00.000Z",
    "last_entry": "2026-03-13T18:30:00.000Z"
  }
}
```

**Tarefas:**
- [x] Implementar `getAuditStats()` em `src/commands/audit.zig`
- [x] Adicionar query `getAuditStats()` em `src/db/queries.zig`
- [x] Criar struct `AuditStats` em `src/models/audit.zig` (novo ficheiro)

---

### 2. Melhorias nos Filtros Existentes (Média Prioridade)

#### 2.1 Task List - Filtros Adicionais ✅
**Local na SPEC:** `SPEC/COMMANDS_REFERENCE.md` (linhas 52-65)

Filtros já implementados:
- `-s, --status <state>`: Filtrar por status ✅
- `-p, --priority <n>`: Prioridade mínima (0-9) ✅
- `--severity <n>`: Severidade mínima (0-9) ✅
- `-l, --limit <n>`: Limitar resultados ✅

**Exemplos da SPEC (testados e funcionando):**
```bash
rmp task list -r <name> -p 5              # priority >= 5 ✅
rmp task list -r <name> --severity 3      # severity >= 3 ✅
rmp task list -r <name> -l 10             # limit to 10 ✅
rmp task list -r <name> -p 5 -l 20        # combined filters ✅
```

**Tarefas:**
- [x] Atualizar `handleTaskCommand` em `src/cli.zig` para parsear novas flags
- [x] Atualizar `listTasks()` em `src/commands/task.zig` para aceitar filtros adicionais
- [x] Adicionar queries parametrizadas em `src/db/queries.zig`:
  - [x] `listTasks()` com `TaskFilterOptions` struct

#### 2.2 Sprint Tasks - Filtro por Status ✅
**Local na SPEC:** `SPEC/COMMANDS_REFERENCE.md` (linhas 171-177)

**Exemplos da SPEC (testados e funcionando):**
```bash
rmp sprint tasks -r <name> 1 --status DOING ✅
rmp sprint tasks -r <name> 1 -s COMPLETED ✅
```

**Tarefas:**
- [x] Atualizar `handleSprintCommand` em `src/cli.zig` para parsear flag de status
- [x] Atualizar `listSprintTasks()` em `src/commands/sprint.zig` para aceitar filtro de status
- [x] Adicionar query `getTasksBySprintFiltered()` em `src/db/queries.zig`

---

## Resumo de Implementação

| Categoria | Implementado | Pendente | % Completo |
|-----------|-------------|----------|------------|
| Roadmap | 4/4 | 0/4 | 100% |
| Task | 8/8 | 0/8* | 100% |
| Sprint | 13/13 | 0/13* | 100% |
| **Audit** | **3/3** | **0/3** | **100%** |

\* Nota: Task e Sprint têm melhorias pendentes nos filtros ✅ (IMPLEMENTADO na Fase 2)

**Progresso Total Estimado**: ~100% do core implementado, **Audit CLI 100%**, **Filtros 100%**

---

## Estrutura de Ficheiros Proposta

### Novos Ficheiros
```
src/
├── commands/
│   └── audit.zig         # NOVO: Audit commands (list, history, stats)
└── models/
    └── audit.zig         # NOVO: Audit models (AuditEntry, AuditStats)
```

### Ficheiros a Atualizar
```
src/
├── cli.zig               # Adicionar handler para comando 'audit'
├── commands/
│   ├── task.zig          # Adicionar filtros em listTasks()
│   └── sprint.zig        # Adicionar filtro em listSprintTasks()
└── db/
    └── queries.zig       # Adicionar queries de audit e filtros
```

---

## Ordem de Implementação Recomendada

### Fase 1: Audit Log Core (Alta Prioridade) 🔥
1. Criar `src/models/audit.zig` com structs `AuditEntry` e `AuditStats`
2. Criar `src/commands/audit.zig` com estrutura base
3. Adicionar queries de audit em `src/db/queries.zig`:
   - `listAuditEntries()` - listagem com filtros
   - `getEntityHistory()` - histórico de entidade
   - `getAuditStats()` - estatísticas
4. Implementar `listAuditEntries()` com filtros básicos (operation, entity-type)
5. Adicionar handler em `src/cli.zig` para comando `audit list`
6. Implementar `getEntityHistory()` e adicionar `audit history`
7. Implementar `getAuditStats()` e adicionar `audit stats`
8. Adicionar filtros de data (--since, --until) e paginação (--offset)

### Fase 2: Melhorias de Filtros (Média Prioridade)
1. Atualizar `task list` com filtros de priority (`-p`) e severity (`--severity`)
2. Atualizar `task list` com limit (`-l`)
3. Atualizar `sprint tasks` com filtro de status (`-s`)

### Fase 3: Polimento (Baixa Prioridade)
1. Validações adicionais de input (datas ISO 8601, limites)
2. Testes de integração para comandos de audit
3. Atualizar documentação

---

## Referências

- **SPEC/COMMANDS.md**: Documentação completa dos comandos (especialmente seção Audit)
- **SPEC/COMMANDS_REFERENCE.md**: Referência rápida com exemplos
- **SPEC/DATA_FORMATS.md**: Formatos de JSON esperados
- **SPEC/DATABASE.md**: Schema da tabela audit

---

## Histórico de Alterações

| Data | Descrição |
|------|-----------|
| 2026-03-13 | Atualizado com funcionalidades pendentes da SPEC - Audit Log (0% implementado) |
| 2026-03-12 | Versão anterior indicava 100% concluído (sem Audit) |
