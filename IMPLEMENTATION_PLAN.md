# Plano de Implementação - LRoadmap CLI

## Status Atual (2026-03-13)

**Resultado da Auditoria:** Foram identificadas **10 inconformidades críticas** com a SPEC que necessitam correção.

---

## Tarefas por Prioridade

### 🔴 ALTA PRIORIDADE (Bloqueantes)

#### Tarefa 1: Corrigir Formato de Resposta JSON de Sucesso

**Identificação:** T001-FIX-SUCCESS-JSON

**Descrição Técnica:**
O formato atual de resposta de sucesso retorna apenas o payload diretamente, sem o wrapper `{"success": true, "data": ...}` conforme especificado em DATA_FORMATS.md. É necessário atualizar a função `success()` em `src/utils/json.zig` e todos os pontos de chamada para incluir o wrapper correto.

**Ficheiros Afetados:**
- `src/utils/json.zig` - Função `success()`
- `src/commands/roadmap.zig` - Todas as funções de comando
- `src/commands/task.zig` - Todas as funções de comando
- `src/commands/sprint.zig` - Todas as funções de comando
- `src/commands/audit.zig` - Todas as funções de comando

**Critérios de Sucesso:**
- [ ] Resposta de sucesso inclui `"success": true`
- [ ] Payload está dentro de um objeto `data`
- [ ] Formato: `{"success": true, "data": {...}}`
- [ ] Exemplo: Criar task retorna `{"success": true, "data": {"id": 1, ...}}`
- [ ] Todos os testes existentes passam com o novo formato
- [ ] Verificar que `zig build test` executa sem falhas

---

#### Tarefa 2: Corrigir Formato de Resposta de Erro

**Identificação:** T002-FIX-ERROR-JSON

**Descrição Técnica:**
O formato atual de erro retorna apenas o objeto de erro sem o wrapper completo. Deve retornar `{"success": false, "error": {"code": "...", "message": "..."}}`. Além disso, os erros devem ser escritos para stderr, não stdout.

**Ficheiros Afetados:**
- `src/utils/json.zig` - Funções `errorResponse()` e `errorResponseWithDetails()`
- `src/main.zig` - Redirecionar erros para stderr (linha 42-43)
- `src/cli.zig` - Atualizar todos os pontos de retorno de erro

**Critérios de Sucesso:**
- [ ] Resposta de erro inclui `"success": false`
- [ ] Objeto de erro está dentro de `error`
- [ ] Formato: `{"success": false, "error": {"code": "...", "message": "..."}}`
- [ ] Erros são escritos para stderr (usar `std.fs.File.stderr()`)
- [ ] Mensagens de erro aparecem em stderr quando redirecionado (`rmp cmd 2>/dev/null`)

---

#### Tarefa 3: Implementar Exibição de Help para Erros de Input

**Identificação:** T003-ADD-HELP-ON-ERROR

**Descrição Técnica:**
Conforme DATA_FORMATS.md, quando ocorrem erros relacionados a inputs (parâmetros em falta, tipos inválidos, comandos desconhecidos), deve ser exibida a mensagem de erro seguida do help do comando. Atualmente apenas é retornado o erro em JSON.

**Ficheiros Afetados:**
- `src/cli.zig` - Adicionar lógica de exibição de help
- Criar estrutura de help por comando

**Critérios de Sucesso:**
- [ ] Erro de parâmetro em falta mostra help do comando após a mensagem de erro
- [ ] Erro de comando desconhecido mostra help geral
- [ ] Erro de subcomando inválido mostra help do comando pai
- [ ] Help aparece em stdout (erro em stderr, help em stdout)
- [ ] Exit code 2 para erros de misuse

---

### 🟠 MÉDIA PRIORIDADE (Funcionalidade)

#### Tarefa 4: Implementar Bulk Operations para Tasks

**Identificação:** T004-IMPL-BULK-OPS

**Descrição Técnica:**
A SPEC define que comandos como `rmp task stat`, `rmp task prio`, `rmp task sev`, e `rmp task rm` devem aceitar múltiplos IDs separados por vírgula (ex: `1,2,3,10`). Atualmente estas funções aceitam apenas um único ID.

**Ficheiros Afetados:**
- `src/cli.zig` - Parse de múltiplos IDs
- `src/commands/task.zig`:
  - `changeTaskStatus()` - Aceitar `[]i64` em vez de `i64`
  - `setPriority()` - Aceitar `[]i64`
  - `setSeverity()` - Aceitar `[]i64`
  - `deleteTask()` - Aceitar `[]i64`
- `src/db/queries.zig` - Queries de update com `WHERE id IN (...)`

**Critérios de Sucesso:**
- [ ] `rmp task stat -r project1 1,2,3 DOING` funciona e atualiza 3 tasks
- [ ] `rmp task prio -r project1 5,6,7 9` funciona e atualiza prioridade de múltiplas tasks
- [ ] `rmp task rm -r project1 1,2,3` remove múltiplas tasks
- [ ] Resposta inclui array de IDs atualizados: `{"updated": [1, 2, 3], "count": 3}`
- [ ] Se um ID não existir, retorna erro indicando IDs em falta
- [ ] Suporte a até 100 IDs por operação

---

#### Tarefa 5: Corrigir Operações Audit na Enum

**Identificação:** T005-FIX-AUDIT-OPS

**Descrição Técnica:**
A enum `OperationType` em `models/audit.zig` usa nomes diferentes dos definidos na SPEC. Além disso, faltam operações como `SPRINT_GET`, `SPRINT_STATS`, etc.

**Mapeamento de Correções:**
| Atual | Correto |
|-------|---------|
| `TASK_ADDED_TO_SPRINT` | `SPRINT_ADD_TASK` |
| `TASK_REMOVED_FROM_SPRINT` | `SPRINT_REMOVE_TASK` |
| `TASK_MOVED_BETWEEN_SPRINTS` | `SPRINT_MOVE_TASK` |
| (falta) | `SPRINT_GET` |
| (falta) | `SPRINT_STATS` |
| (falta) | `SPRINT_LIST_TASKS` |

**Ficheiros Afetados:**
- `src/models/audit.zig` - Atualizar enum `OperationType`
- `src/commands/sprint.zig` - Atualizar chamadas a `logOperation()`
- `src/commands/task.zig` - Atualizar chamadas se necessário

**Critérios de Sucesso:**
- [ ] Enum contém todas as operações da SPEC
- [ ] Nomes coincidem exatamente com DATA_FORMATS.md linhas 372-398
- [ ] Todas as operações de sprint são logadas com nomes corretos
- [ ] Testes verificam que os nomes das operações estão corretos

---

#### Tarefa 6: Corrigir Ordenação de Tasks em Sprint

**Identificação:** T006-FIX-SPRINT-ORDER

**Descrição Técnica:**
Conforme SPEC (DATA_FORMATS.md:349-353), as tasks num sprint devem ser ordenadas por `priority DESC, severity DESC`. Atualmente está ordenado por `priority DESC, created_at ASC`.

**Ficheiros Afetados:**
- `src/db/queries.zig` - Função `getTasksBySprint()` (linha ~430)
- Verificar também `getTasksBySprintFiltered()`

**Critérios de Sucesso:**
- [ ] Query usa `ORDER BY t.priority DESC, t.severity DESC`
- [ ] Tasks com mesma prioridade são ordenadas por severidade (mais alta primeiro)
- [ ] Testes verificam a ordem correta no output JSON

---

#### Tarefa 7: Completar Sprint Stats

**Identificação:** T007-COMPLETE-SPRINT-STATS

**Descrição Técnica:**
O objeto de resposta de sprint stats está incompleto. Falta incluir: `description`, `status`, `created_at`, `started_at`, `closed_at`.

**Ficheiros Afetados:**
- `src/commands/sprint.zig` - Função `getSprintStats()` (linha ~465)
- `src/db/queries.zig` - Query `getSprintStats()` (linha ~638) - precisa fazer JOIN com sprints

**Critérios de Sucesso:**
- [ ] Resposta inclui `description`, `status`, `created_at`, `started_at`, `closed_at`
- [ ] Formato conforme SPEC (COMMANDS.md:537-558)
- [ ] Datas em formato ISO 8601
- [ ] Valores null para datas não definidas

---

### 🟡 BAIXA PRIORIDADE (Qualidade)

#### Tarefa 8: Adicionar Transações SQL em Operações Compostas

**Identificação:** T008-ADD-TRANSACTIONS

**Descrição Técnica:**
Operações que envolvem múltiplas queries (ex: adicionar task a sprint + atualizar status) devem usar transações para garantir consistência. Atualmente se falhar no meio, o estado fica inconsistente.

**Ficheiros Afetados:**
- `src/commands/sprint.zig`:
  - `addTaskToSprint()` - Usar transação para `addTaskToSprint` + `updateTaskStatus`
  - `removeTaskFromSprint()` - Usar transação para `removeTaskFromSprint` + `updateTaskStatus`
  - `moveTaskBetweenSprints()` - Usar transação

**Critérios de Sucesso:**
- [ ] Operações usam `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK`
- [ ] Se uma parte falha, é feito rollback
- [ ] Testes simulam falhas e verificam consistência

---

#### Tarefa 9: Validar Range de Prioridade/Severidade (0-9)

**Identificação:** T009-VALIDATE-RANGES

**Descrição Técnica:**
As funções `setPriority()` e `setSeverity()` devem validar que os valores estão entre 0-9 antes de atualizar. A validação existe no modelo (Task.setPriority) mas não é usada nos comandos.

**Ficheiros Afetados:**
- `src/commands/task.zig` - Funções `setPriority()` e `setSeverity()`
- `src/cli.zig` - Validação prévia dos argumentos

**Critérios de Sucesso:**
- [ ] Valores < 0 ou > 9 retornam erro `INVALID_PRIORITY` ou `INVALID_SEVERITY`
- [ ] Exit code 6 para dados inválidos
- [ ] Mensagem de erro clara indica o range válido (0-9)

---

#### Tarefa 10: Corrigir Duplicação de Log em Roadmap Create

**Identificação:** T010-FIX-DUPLICATE-LOG

**Descrição Técnica:**
Em `roadmap.zig` linhas 131-135, a operação `ROADMAP_CREATE` é logada duas vezes.

**Ficheiros Afetados:**
- `src/commands/roadmap.zig` - Remover linha duplicada 135

**Critérios de Sucesso:**
- [ ] Código duplicado removido
- [ ] Apenas uma entrada de audit por roadmap criado

---

## Tarefas Adicionais (Melhorias)

### Tarefa 11: Adicionar Alias `aud` para Comando Audit

**Identificação:** T011-ADD-AUDIT-ALIAS

**Descrição Técnica:**
Adicionar o alias curto `aud` para o comando `audit`, conforme mencionado na SPEC (COMMANDS.md:825).

**Critérios de Sucesso:**
- [ ] `rmp aud list` funciona como `rmp audit list`
- [ ] `rmp aud hist` funciona como `rmp audit history`
- [ ] `rmp aud stats` funciona como `rmp audit stats`

---

### Tarefa 12: Melhorar Validação de Binding SQLite

**Identificação:** T012-VALIDATE-SQLITE-BIND

**Descrição Técnica:**
Verificar códigos de retorno de `sqlite3_bind_*` em vez de ignorar com `_ =`.

**Ficheiros Afetados:**
- `src/db/queries.zig` - Todas as funções que fazem bind

**Critérios de Sucesso:**
- [ ] Verificar se `sqlite3_bind_*` retorna `SQLITE_OK`
- [ ] Retornar erro apropriado se binding falhar

---

## Resumo de Implementação

| Categoria | Tarefas | Prioridade | % Completo |
|-----------|---------|------------|------------|
| **Alta** | 4 | 🔴 | 100% |
| **Média** | 4 | 🟠 | 100% |
| **Baixa** | 3 | 🟡 | 100% |
| **Melhorias** | 2 | ⚪ | 100% |

**Progresso Total:** 100%

### Tarefas Concluídas

- **T010** ✅ - Corrigir duplicação de log em roadmap.zig
- **T002** ✅ - Corrigir formato de erro JSON (wrapper + stderr)
- **T001** ✅ - Corrigir formato de sucesso JSON (wrapper)
- **T003** ✅ - Implementar help em erros de input
- **T006** ✅ - Corrigir ordenação de tasks em sprint
- **T005** ✅ - Corrigir enum OperationType em audit.zig
- **T004** ✅ - Implementar bulk operations para tasks
- **T007** ✅ - Completar sprint stats (já estava implementado)
- **T008** ✅ - Adicionar transações SQL em operações compostas
- **T009** ✅ - Validar ranges de prioridade/severidade (0-9)
- **T011** ✅ - Adicionar alias `aud` para comando audit
- **T012** ✅ - Validar SQLite binds (funções helper criadas)

---

---

## Ordem de Implementação Recomendada

### Fase 1: Correções Críticas (Alta Prioridade)
1. **T010** - Corrigir duplicação (rápido)
2. **T002** - Corrigir formato de erro JSON
3. **T001** - Corrigir formato de sucesso JSON
4. **T003** - Implementar help em erros de input

### Fase 2: Funcionalidades Média Prioridade
5. **T006** - Corrigir ordenação de tasks
6. **T005** - Corrigir operações audit
7. **T004** - Implementar bulk operations
8. **T007** - Completar sprint stats

### Fase 3: Qualidade e Robustez
9. **T009** - Validar ranges
10. **T008** - Adicionar transações
11. **T011** - Alias audit
12. **T012** - Validar SQLite binds

---

## Referências

- **SPEC/COMMANDS.md**: Documentação completa dos comandos
- **SPEC/COMMANDS_REFERENCE.md**: Referência rápida com exemplos
- **SPEC/DATA_FORMATS.md**: Formatos de JSON esperados (fonte da maior parte das inconformidades)
- **SPEC/DATABASE.md**: Schema da base de dados
- **SPEC/ARCHITECTURE.md**: Arquitetura do sistema

---

## Notas da Auditoria

| ID | Inconformidade | Local | Severidade |
|----|----------------|-------|------------|
| INF001 | Formato JSON sucesso incorreto | `json.zig` | 🔴 Alta |
| INF002 | Formato JSON erro incorreto | `json.zig` | 🔴 Alta |
| INF003 | Erros vão para stdout | `main.zig:42-43` | 🔴 Alta |
| INF004 | Operações audit não conforme | `models/audit.zig` | 🟠 Média |
| INF005 | Bulk operations não implementadas | `task.zig` | 🟠 Média |
| INF006 | Sprint stats incompleto | `sprint.zig:480-494` | 🟠 Média |
| INF007 | Ordenação sprint tasks incorreta | `queries.zig:436` | 🟠 Média |
| INF008 | Sem transações | `sprint.zig`, `task.zig` | 🟡 Baixa |
| INF009 | Falta validação range | `task.zig` | 🟡 Baixa |
| INF010 | Código duplicado | `roadmap.zig:131-135` | 🟡 Baixa |

---

## Histórico de Alterações

| Data | Descrição |
|------|-----------|
| 2026-03-13 | Plano atualizado após auditoria exaustiva - identificadas 10 inconformidades críticas |
| 2026-03-12 | Versão anterior (funcionalidades implementadas) |
