# Plano de Implementação - LRoadmap CLI

## Status Atual (2026-03-13)

**Resultado da Auditoria Exaustiva:** Foram identificadas inconformidades críticas de performance e segurança, além de inconsistências com a SPEC. O código apresenta problemas desde a criação do schema (faltam índices), tratamento de erros inconsistente, e violações da especificação. O projeto necessita de correções fundamentais na camada de persistência e tratamento de erros.

---

## Tarefas por Prioridade

### 🔴 CRÍTICA (Bloqueantes & Performance)

#### Tarefa 1: Criar Índices SQLite (CRÍTICO - Performance)
**Identificação:** T001-CREATE-SQLITE-INDEXES
**Necessidade:** A SPEC (DATABASE.md:77-80,96-97,114-115,131-134) define 9 índices essenciais para queries eficientes, mas o schema.zig NÃO os cria. Sem estes índices, operações de filtro (`--status`, `--priority`, `--since`) farão full table scans, tornando o sistema inutilizável com bases de dados grandes.
**Descrição Técnica:** Adicionar à função `createSchema()` em `src/db/schema.zig` as instruções CREATE INDEX:
```sql
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at);
CREATE INDEX IF NOT EXISTS idx_sprints_status ON sprints(status);
CREATE INDEX IF NOT EXISTS idx_sprints_created_at ON sprints(created_at);
CREATE INDEX IF NOT EXISTS idx_sprint_tasks_task_id ON sprint_tasks(task_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_operation ON audit(operation);
CREATE INDEX IF NOT EXISTS idx_audit_performed_at ON audit(performed_at);
```
**Ficheiros Afetados:** `src/db/schema.zig`
**Critérios de Sucesso:**
- [ ] Todos os 9 índices são criados aquando da criação do schema.
- [ ] Queries com filtros por status, priority, entity_type são rápidas.
**Validação:**
```bash
sqlite3 ~/.roadmaps/test.db "SELECT name FROM sqlite_master WHERE type='index';"
# Deve retornar todos os 9 índices
rmp task list -r test --status DOING  # Deve usar índice (EXPLAIN QUERY PLAN)
```

#### Tarefa 2: Otimização de Performance e Robustez SQLite
**Identificação:** T002-SQLITE-PERF-TUNING
**Necessidade:** A conexão SQLite atual é sub-ótima. Sem WAL mode e busy_timeout, acessos simultâneos de leitura/escrita podem bloquear. A SPEC menciona "Prepared statements" e "Lazy loading" como requisitos de performance.
**Descrição Técnica:** Implementar PRAGMAS na abertura da conexão em `src/db/connection.zig:open()`:
```zig
try conn.exec("PRAGMA journal_mode = WAL");
try conn.exec("PRAGMA synchronous = NORMAL");
try conn.exec("PRAGMA busy_timeout = 5000");
try conn.exec("PRAGMA foreign_keys = ON");
```
**Ficheiros Afetados:** `src/db/connection.zig`
**Critérios de Sucesso:**
- [ ] O sistema não bloqueia em acessos simultâneos de leitura/escrita.
- [ ] Performance de operações bulk melhorada.
**Validação:** Testar com script que faz leituras e escritas concorrentes. Medir tempo de operações bulk com `time`.

#### Tarefa 3: Corrigir Entity Types em Operações Audit (VIOLAÇÃO SPEC)
**Identificação:** T003-FIX-ENTITY-TYPE-CASE
**Necessidade:** A SPEC (DATABASE.md:139,168) define claramente que `entity_type` deve ser `'TASK'` ou `'SPRINT'` (maiúsculas). O código usa minúsculas `"task"`, `"sprint"`, `"roadmap"` violando a especificação. Isso quebra queries de auditoria.
**Descrição Técnica:** Substituir todas as strings literais minúsculas por maiúsculas:
- `src/commands/task.zig:51`: `"task"` → `"TASK"`
- `src/commands/task.zig:225`: `"task"` → `"TASK"`
- `src/commands/task.zig:300`: `"task"` → `"TASK"`
- `src/commands/task.zig:375`: `"task"` → `"TASK"`
- `src/commands/task.zig:477`: `"task"` → `"TASK"`
- `src/commands/sprint.zig:48`: `"sprint"` → `"SPRINT"`
- `src/commands/sprint.zig:112,115,181`: `"sprint"` → `"SPRINT"`
- `src/commands/sprint.zig:290,352,457,570,605`: `"sprint"` → `"SPRINT"`
- `src/commands/roadmap.zig:132`: `"roadmap"` → `"ROADMAP"` (ou remover se não especificado)
**Ficheiros Afetados:** `src/commands/task.zig`, `src/commands/sprint.zig`, `src/commands/roadmap.zig`
**Critérios de Sucesso:**
- [ ] Todas as chamadas a `logOperation` usam maiúsculas.
- [ ] `SELECT DISTINCT entity_type FROM audit;` retorna apenas `TASK`, `SPRINT`.
**Validação:** Executar operações e verificar audit log: `rmp audit list -r test -e TASK`

#### Tarefa 4: Atomicidade e Transações em Operações de Escrita Bulk
**Identificação:** T004-DB-TRANSACTIONS
**Necessidade:** Operações bulk (changeTaskStatus, setPriority, setSeverity, deleteTask) atualizam múltiplos registos sem transação. Se falhar a meio, ficam dados inconsistentes. A SPEC menciona "atomicidade" como requisito.
**Descrição Técnica:** Envolver operações bulk em transações SQL explícitas:
```zig
try conn.beginTransaction();
// ... loop de updates ...
try conn.commit();
// Em caso de erro: try conn.rollback();
```
**Ficheiros Afetados:** `src/commands/task.zig` (changeTaskStatus, setPriority, setSeverity, deleteTask)
**Critérios de Sucesso:**
- [ ] Garantia de "Tudo ou Nada" em operações bulk.
- [ ] Rollback automático em caso de falha.
**Validação:** Simular falha no meio de operação bulk e verificar que Rollback preserva estado anterior.

#### Tarefa 5: Auditoria Mandatária - Remover `catch {}`
**Identificação:** T005-AUDIT-HARDENING
**Necessidade:** O log de auditoria é crítico para rastreabilidade. O código atual silencia erros de auditoria com `catch {}`, permitindo que operações sejam executadas sem registo. Isso viola o requisito de "Complete Audit" da SPEC.
**Descrição Técnica:** Remover todos os `catch {}` de chamadas `logOperation`. O erro de auditoria deve propagar e falhar a operação:
```zig
// ANTES (errado):
queries.logOperation(conn, "TASK_CREATE", "task", task_id, now) catch {};

// DEPOIS (correto):
try queries.logOperation(conn, "TASK_CREATE", "TASK", task_id, now);
```
**Referências:**
- `src/commands/roadmap.zig:132`
- `src/commands/sprint.zig:48,112,115,181`
**Ficheiros Afetados:** `src/commands/roadmap.zig`, `src/commands/sprint.zig`
**Critérios de Sucesso:**
- [ ] Integridade absoluta do log de auditoria.
- [ ] Operações falham se audit log falhar.
**Validação:** Forçar erro na tabela audit (ex: tabela bloqueada) e verificar que operações falham com erro apropriado.

---

### 🟠 ALTA PRIORIDADE (Conformidade & Qualidade)

#### Tarefa 6: Corrigir Formato de Sprint Stats (SPEC Compliance)
**Identificação:** T006-FIX-SPRINT-STATS-FORMAT
**Necessidade:** A SPEC (COMMANDS.md:537) define que o JSON de resposta de sprint stats deve usar `"sprint_id"` mas o código usa `"id"`. Isso quebra integrações que esperam o formato especificado.
**Descrição Técnica:** Alterar linha em `src/commands/sprint.zig:533`:
```zig
// ANTES:
\\{{"id":{d},...

// DEPOIS:
\\{{"sprint_id":{d},...
```
**Ficheiros Afetados:** `src/commands/sprint.zig:533-548`
**Critérios de Sucesso:**
- [ ] Saída JSON usa `"sprint_id"` conforme COMMANDS.md:537.
**Validação:** `rmp sprint stats -r project1 1 | jq '.sprint_id'` deve retornar o ID.

#### Tarefa 7: Validar Transições de Estado Task
**Identificação:** T007-USE-TASK-STATUS-VALIDATION
**Necessidade:** O modelo `TaskStatus.isValidTransition()` existe mas não é usado. A SPEC define o fluxo: `BACKLOG → SPRINT → DOING → TESTING → COMPLETED`. Transições inválidas como `BACKLOG → COMPLETED` devem ser rejeitadas.
**Descrição Técnica:** Adicionar validação em `changeTaskStatus()` antes de atualizar:
```zig
const current_status = try queries.getTaskStatus(conn, task_id);
if (!current_status.isValidTransition(new_status)) {
    return json.errorResponse(allocator, "INVALID_STATUS_TRANSITION",
        "Cannot transition from BACKLOG to COMPLETED");
}
```
**Ficheiros Afetados:** `src/commands/task.zig:164-244`, `src/db/queries.zig`
**Critérios de Sucesso:**
- [ ] Transições inválidas são rejeitadas com erro apropriado.
- [ ] Mensagem de erro indica estados válidos.
**Validação:** Testar `rmp task stat -r test 1 COMPLETED` quando task está em BACKLOG. Deve falhar.

#### Tarefa 8: Ciclo de Vida do Sprint - Preencher closed_at
**Identificação:** T008-FIX-SPRINT-LIFECYCLE-DATES
**Necessidade:** Quando um sprint fecha, `closed_at` deve ser preenchido. Quando reabre, deve ser limpo. O código atual em `closeSprint()` não define `closed_at`, e `reopenSprint()` já limpa mas precisa verificação.
**Descrição Técnica:**
- Em `closeSprint()`: adicionar `try queries.updateSprintClosedAt(conn, sprint_id, now);`
- Verificar que `reopenSprint()` limpa `closed_at` (já implementado na linha 489).
**Ficheiros Afetados:** `src/commands/sprint.zig:176-181`
**Critérios de Sucesso:**
- [ ] `closed_at` preenchido após `sprint close`.
- [ ] `closed_at` = null após `sprint reopen`.
**Validação:** Verificar na base de dados após transições de estado.

#### Tarefa 9: Adicionar Campo "roadmap" em Sprint List
**Identificação:** T009-FIX-SPRINT-LIST-RESPONSE
**Necessidade:** Para consistência com `listTasks`, a resposta de `listSprints` deve incluir o campo `"roadmap"`.
**Descrição Técnica:** Modificar `src/commands/sprint.zig:235` para incluir:
```zig
const result = try std.fmt.allocPrint(allocator,
    "{{\"roadmap\":\"{s}\",\"count\":{d},\"sprints\":[{s}]}}",
    .{ current, sprints.len, sprints_str });
```
**Ficheiros Afetados:** `src/commands/sprint.zig:235`
**Critérios de Sucesso:**
- [ ] Response inclui `"roadmap":"<name>"`.
**Validação:** `rmp sprint list -r project1 | jq '.roadmap'` retorna nome do roadmap.

#### Tarefa 10: Erros em Plain Text para Stderr
**Identificação:** T010-FIX-ERROR-OUTPUT-FORMAT
**Necessidade:** A SPEC (DATA_FORMATS.md:14-17, COMMANDS.md:16-17) define que erros vão para stderr em plain text, não JSON. O handler de erros em main.zig usa JSON.
**Descrição Técnica:** Modificar `src/main.zig:35-44` para escrever plain text em stderr:
```zig
cli.run(allocator, args) catch |err| {
    const stderr = std.fs.File.stderr().deprecatedWriter();
    stderr.print("Error: {s}\n", .{@errorName(err)}) catch {};
    std.process.exit(1);
};
```
**Ficheiros Afetados:** `src/main.zig:35-44`
**Critérios de Sucesso:**
- [ ] Erros fatais em main são plain text para stderr.
**Validação:** Provocar erro e verificar output: `rmp invalid-command 2>&1 | head -1`

---

### 🟡 MÉDIA PRIORIDADE (Manutenibilidade & Refatoração)

#### Tarefa 11: Implementar Help em JSON Estruturado
**Identificação:** T011-IMPL-STRUCTURED-HELP
**Necessidade:** A SPEC (DATA_FORMATS.md:628-676) define que help deve retornar JSON estruturado com command, description, usage, options, examples. Atualmente é plain text.
**Descrição Técnica:** Reimplementar help em `src/cli.zig` para retornar:
```json
{
  "command": "task create",
  "description": "Creates a new task...",
  "usage": "rmp task create [OPTIONS]",
  "options": [...],
  "examples": [...]
}
```
**Ficheiros Afetados:** `src/cli.zig:91-93, 139-142` e funções de help associadas
**Critérios de Sucesso:**
- [ ] `rmp --help` e `rmp task create --help` retornam JSON válido.
**Validação:** `rmp task create --help | jq .` produz JSON válido.

#### Tarefa 12: Migração Global para ArrayListUnmanaged (Zig 0.15)
**Identificação:** T012-MIGRATE-ARRAYLIST-UNMANAGED
**Necessidade:** Zig 0.15 prefere `std.ArrayListUnmanaged` para melhor performance. `src/utils/path.zig:138` ainda usa `std.ArrayList([]const u8).init(allocator)`.
**Descrição Técnica:** Converter todos os `std.ArrayList(T)` restantes para `std.ArrayListUnmanaged(T)`:
```zig
// ANTES:
var names = std.ArrayList([]const u8).init(allocator);

// DEPOIS:
var names: std.ArrayListUnmanaged([]const u8) = .empty;
defer names.deinit(allocator);
```
**Ficheiros Afetados:** `src/utils/path.zig:138` e outros usos remanescentes
**Critérios de Sucesso:**
- [ ] Código compila sem warnings de depreciação.
- [ ] Testes passam.
**Validação:** `zig build test` sem erros.

#### Tarefa 13: Eliminar Duplicação de Código
**Identificação:** T013-REMOVE-DUPLICATED-CODE
**Necessidade:** A função `isValidSQLiteFile` existe em dois ficheiros (`connection.zig:90-101` e `path.zig:97-108`), violando DRY.
**Descrição Técnica:** Manter apenas em `connection.zig` e remover de `path.zig`. Atualizar importações se necessário.
**Ficheiros Afetados:** `src/db/connection.zig`, `src/utils/path.zig`
**Critérios de Sucesso:**
- [ ] Apenas uma implementação de `isValidSQLiteFile`.
- [ ] Testes passam.
**Validação:** `grep -r "isValidSQLiteFile" src/` retorna apenas uma definição.

#### Tarefa 14: Sprint Tasks Deve Retornar Campo roadmap
**Identificação:** T014-FIX-SPRINT-TASKS-RESPONSE
**Necessidade:** `sprint tasks` deve incluir campo `"roadmap"` e ordenar por priority DESC, severity DESC conforme SPEC (COMMANDS.md:420-468).
**Descrição Técnica:** Verificar e corrigir `listSprintTasks()` para incluir campo roadmap e ordenação correta.
**Ficheiros Afetados:** `src/commands/sprint.zig:399-437`
**Critérios de Sucesso:**
- [ ] Response inclui `"roadmap"`.
- [ ] Tasks ordenadas por priority DESC, severity DESC.
**Validação:** `rmp sprint tasks -r test 1 | jq '.roadmap'` e verificar ordenação.

---

### 🟢 BAIXA PRIORIDADE (Melhorias Opcionais)

#### Tarefa 15: Implementar Prepared Statements Cache
**Identificação:** T015-PREPARED-STATEMENTS-CACHE
**Necessidade:** A SPEC (ARCHITECTURE.md:209) menciona "Prepared statements: Pre-compiled SQLite queries" como requisito de performance.
**Descrição Técnica:** Implementar cache de prepared statements para queries frequentes.
**Ficheiros Afetados:** `src/db/queries.zig`
**Critérios de Sucesso:**
- [ ] Prepared statements reutilizados entre chamadas.
**Validação:** Benchmark de operações repetidas.

#### Tarefa 16: Adicionar Testes de Integração
**Identificação:** T016-INTEGRATION-TESTS
**Necessidade:** Testes unitários existem mas não cobrem cenários de integração E2E.
**Descrição Técnica:** Criar testes que exercitam fluxos completos: create → list → update → delete.
**Ficheiros Afetados:** Novo ficheiro `tests/integration.zig`
**Critérios de Sucesso:**
- [ ] Fluxos completos testados.
**Validação:** `zig build test` inclui testes de integração.

---

## Matriz de Rastreabilidade (SPEC vs Tarefa)

| Requisito SPEC | Tarefa | Prioridade |
|----------------|--------|------------|
| Database Indexes (DATABASE.md:77-80,96-97,114-115,131-134) | T001 | CRÍTICA |
| SQLite PRAGMAs (Performance) | T002 | CRÍTICA |
| Audit Entity Types maiúsculos (DATABASE.md:139,168) | T003 | CRÍTICA |
| Atomicidade em bulk operations | T004 | CRÍTICA |
| Audit mandatory (não falhar silenciosamente) | T005 | CRÍTICA |
| Sprint stats "sprint_id" (COMMANDS.md:537) | T006 | ALTA |
| Task status validation (SPEC: status flow) | T007 | ALTA |
| Sprint closed_at lifecycle | T008 | ALTA |
| Sprint list roadmap field | T009 | ALTA |
| Error plain text to stderr (DATA_FORMATS.md:14-17) | T010 | ALTA |
| Help em JSON (DATA_FORMATS.md:628) | T011 | MÉDIA |
| ArrayListUnmanaged (Zig 0.15) | T012 | MÉDIA |
| DRY - isValidSQLiteFile | T013 | MÉDIA |
| Sprint tasks roadmap + ordering | T014 | MÉDIA |
| Prepared statements (ARCHITECTURE.md:209) | T015 | BAIXA |
| Integration tests | T016 | BAIXA |

---

## Notas de Implementação

### Padrões Críticos Zig 0.15
1. **SQLite C API:** Sempre use `@ptrCast(conn.db)` para passar para funções C.
2. **Memória:** Use `std.ArrayListUnmanaged` com allocator explícito.
3. **Atomicidade:** Sempre abra transação antes de loops de escrita.
4. **Dates:** ISO 8601 UTC garantido por `utils/time.zig`.
5. **JSON:** Considerar migrar para `std.json.stringify` se volume aumentar.

### Ficheiros com Problemas Críticos
- `src/db/schema.zig` - NÃO CRIA ÍNDICES (T001)
- `src/db/connection.zig` - PRAGMAS INCOMPLETOS (T002)
- `src/commands/task.zig` - SEM TRANSAÇÕES (T004), ENTITY TYPES MINÚSCULOS (T003)
- `src/commands/roadmap.zig:132` - `catch {}` (T005)
- `src/commands/sprint.zig:48,112,115,181` - `catch {}` (T005), ENTITY TYPES MINÚSCULOS (T003)

### Fluxo de Status Task (SPEC)
```
BACKLOG → SPRINT → DOING → TESTING → COMPLETED
    ↓         ↓        ↓        ↓
 BACKLOG  BACKLOG  SPRINT   DOING
```
Transições inválidas: BACKLOG → DOING, BACKLOG → COMPLETED, etc.

### Fluxo de Status Sprint (SPEC)
```
PENDING → OPEN → CLOSED
            ↑        ↓
            └────────┘ (reopen)
```

---

*Plano atualizado após auditoria exaustiva em 2026-03-13.*