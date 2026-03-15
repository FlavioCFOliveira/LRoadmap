# Plano de Implementação: Conformidade com a SPEC do LRoadmap

## Contexto
Este plano visa alinhar a CLI LRoadmap integralmente com a sua especificação técnica (SPEC). O objetivo é garantir um comportamento previsível e padronizado para integração com fluxos de trabalho agenticos, corrigindo formatos de output, completando aliases de comandos e aumentando a precisão temporal.

## Mudanças Propostas

### 1. Refatoração do Sistema de Output (Prioridade Crítica) 🔄 PARCIALMENTE CONCLUÍDO

**Status:** 🔄 Parcialmente Concluído em 2026-03-14

- **JSON Direto para Queries e Criação**:
  - Modificar `src/utils/json.zig` para remover o wrapper `{"status": "success", "data": ...}`.
  - Comandos de consulta (`list`, `get`, `stats`, `history`) devem retornar o objeto ou array JSON diretamente no `stdout`.
  - Comandos de criação devem retornar apenas o objeto de identificação (ex: `{"id": 42}`).

- **Silenciamento de Comandos de Modificação**:
  - Garantir que comandos que alteram o estado (status, prioridade, remoção, início/fim de sprint) não produzam qualquer output no `stdout` em caso de sucesso.

- **Erros em Texto Simples no Stderr** ✅:
  - ✅ Refatorar `printError` e `printErrorWithHelp` em `src/cli.zig` para emitir mensagens em texto simples para o `stderr`.
  - ✅ Erros de input devem ser seguidos pelo texto de ajuda específico do comando.
  - ⏸️ PENDENTE: Converter erros JSON para texto simples nos ficheiros `src/commands/*.zig`

### 2. Implementação de Aliases de Comando (Faltantes) 🔄 PARCIALMENTE CONCLUÍDO

**Status:** 🔄 Parcialmente Concluído em 2026-03-14

- Implementar e validar os seguintes aliases conforme a SPEC:
  - `roadmap`: `road` ✅, `ls` ✅, `new` ✅, `rm` ✅, `delete` ✅.
  - `task`: `ls` ✅, `new` ✅, `create` ✅, `stat` ✅, `prio` ✅, `priority` ✅, `sev` ✅, `severity` ✅, `rm` ✅, `delete` ✅.
  - `sprint`: `ls` ✅, `new` ✅, `upd` ✅, `start` ✅, `add-task` ✅, `add-tasks` ✅, `rm-tasks` ✅, `mv-tasks` ✅.
  - `audit`: `aud` ✅, `ls` ✅, `hist` ✅.

### 3. Precisão de Milissegundos em Timestamps
- Atualizar `src/utils/time.zig` para capturar milissegundos reais usando `std.time.milliTimestamp()`.
- Ajustar `ISO8601_FORMAT` para incluir a fração de segundos com 3 dígitos (`.sss`).
- Garantir que todos os logs de auditoria e campos de data (`created_at`, `completed_at`, etc.) utilizem esta nova precisão.

### 4. Validação de Operações Bulk
- Verificar se todos os comandos que aceitam IDs múltiplos (ex: `1,2,3`) estão a processar a lista corretamente e sem produzir output desnecessário para cada item.

---

## Novas Tarefas Identificadas nos Testes Exaustivos

### Tarefa 4: Implementar Sistema de Help e Exit Codes (Concluída) ✅

**Descrição Técnica:**
Implementar sistema de help completo conforme SPEC (HELP_EXAMPLES.md) com formato texto simples (não JSON) e exit codes padronizados.

**Implementação Realizada:**
1. **Help em formato texto simples** (`src/cli.zig`):
   - `printUsage()` / `printUsageStderr()` - help global
   - `printCommandHelp()` / `printCommandHelpStderr()` - help de comandos (roadmap, task, sprint, audit)
   - `printSubcommandHelp()` - help específico para cada subcomando

2. **Suporte a `-h/--help` em todos os níveis**:
   - Global: `rmp --help`
   - Comando: `rmp task --help`
   - Subcomando: `rmp task create --help`

3. **Exit codes conforme SPEC** (DATA_FORMATS.md:76-88):
   - `0` - Sucesso
   - `1` - Erro geral (falha de banco de dados)
   - `2` - Uso inválido (MISUSE)
   - `3` - Nenhum roadmap selecionado
   - `4` - Não encontrado (NOT_FOUND)
   - `5` - Já existe (EXISTS)
   - `6` - Dados inválidos (INVALID_DATA)
   - `127` - Comando desconhecido

4. **Mensagens de erro com help**:
   - `printError()` - exibe erro em texto simples no stderr
   - `printErrorWithHelp()` - exibe erro + help do comando
   - `printErrorWithSubcommandHelp()` - exibe erro + help específico do subcomando

**Status:** ✅ Concluído em 2026-03-14

**Validação:**
```bash
rmp --help                          # Help global em texto ✅
rmp task --help                     # Help do comando em texto ✅
rmp task create --help              # Help do subcomando em texto ✅
rmp task create 2>&1 | grep -q "^{" && echo "FAIL" || echo "PASS"  # Erros em texto ✅
rmp invalidcmd; echo $?             # Retorna 127 ✅
rmp task get 99999; echo $?         # Retorna 4 ✅
```

---

### Tarefa 5: Correção de Memory Leaks (Prioridade Crítica)

**Descrição Técnica:**
O General Purpose Allocator (GPA) do Zig detectou vazamentos de memória em múltiplas operações. Os leaks ocorrem em caminhos de erro e sucesso quando strings alocadas não são libertadas antes do retorno ou `std.process.exit()`.

**Problemas Identificados:**
- `src/commands/task.zig:152` - `changeTaskStatus`: leak em `errorResponseWithDetails` quando tasks não são encontradas
- `src/commands/task.zig:264` - `setPriority`: leak em `errorResponseWithDetails` quando tasks não são encontradas
- `src/commands/task.zig:351` - `setSeverity`: leak em `errorResponseWithDetails` quando tasks não são encontradas
- `src/commands/sprint.zig:121` - `openSprint`: leak em `json.success` no caminho de sucesso
- `src/commands/sprint.zig:190` - `closeSprint`: leak em `json.success` no caminho de sucesso
- `src/commands/sprint.zig:501` - `reopenSprint`: leak em `json.success` no caminho de sucesso

**Implementação Requerida:**
1. Em `src/commands/task.zig`, garantir que todas as strings alocadas (especialmente `details` e `msg`) são libertadas antes de retornar `errorResponseWithDetails`
2. Em `src/commands/sprint.zig`, revisar o uso de `json.success` para garantir que o allocator libertou a memória antes do retorno
3. Verificar se `defer allocator.free()` está sendo aplicado corretamente em todas as strings alocadas com `std.fmt.allocPrint`
4. Considerar o uso de `errdefer` para libertar memória em caminhos de erro

**Validação:**
```bash
# Executar comandos que anteriormente causavam leaks e verificar que não há mais mensagens "error(gpa): memory address ... leaked"
HOME=/tmp/test_leak rmp task stat 99999 SPRINT 2>&1 | grep -v "leaked"
HOME=/tmp/test_leak rmp sprint start 99999 2>&1 | grep -v "leaked"
HOME=/tmp/test_leak rmp sprint close 1 2>&1 | grep -v "leaked"
```

---

### Tarefa 6: Adicionar Alias `task create` (Prioridade Alta)

**Descrição Técnica:**
A SPEC (COMMANDS.md:125) documenta o comando `rmp task create`, mas a implementação atual só aceita `task add` e `task new`. Isto cria inconsistência entre a documentação e a implementação.

**Implementação Requerida:**
1. Em `src/cli.zig`, na função `handleTaskCommand`, adicionar `"create"` como alias para o handler de `task add`
2. Linha de referência: ~309 em `src/cli.zig`
3. Modificar: `} else if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {`
4. Para: `} else if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new") or std.mem.eql(u8, subcmd, "create")) {`

**Validação:**
```bash
rmp roadmap create test-create && rmp roadmap use test-create
rmp task create --description "Test" --action "Action" --expected-result "Result"
# Deve retornar: {"id": 1}
rmp task list
# Deve mostrar a task criada
```

---

### Tarefa 7: Separar `sprint create` de `sprint add` (Prioridade Alta)

**Descrição Técnica:**
Atualmente `sprint add` é usado para criar sprints (com descrição como argumento posicional), o que é ambíguo e inconsistente com a SPEC. A SPEC (COMMANDS.md:166) define `sprint create` para criar sprints e `sprint add` para adicionar tasks.

**Implementação Requerida:**
1. Em `src/cli.zig`, na função `handleSprintCommand`:
   - Modificar o handler atual de `"add"` para responder a `"create"` ou `"new"` (criação de sprints)
   - Criar novo handler para `"add"` que aceita `<sprint-id> <task-ids>` para adicionar tasks a sprints
2. O novo comando `sprint add` deve:
   - Aceitar argumentos: `<sprint-id> <task-id1,task-id2,...>`
   - Chamar `sprint.addTaskToSprint(allocator, sprint_id, task_id)` para cada task
   - Atualizar o status das tasks para `SPRINT`
   - Logar operação `SPRINT_ADD_TASK` no audit

**Validação:**
```bash
rmp roadmap create test-sprint && rmp roadmap use test-sprint
# Criar sprint
rmp sprint create "Sprint 1"
# Deve retornar: {"id": 1}

# Criar tasks
rmp task add -d "Task 1" -a "Action" -e "Result"
rmp task add -d "Task 2" -a "Action" -e "Result"

# Adicionar tasks ao sprint
rmp sprint add 1 1,2
# Deve retornar sucesso sem output

# Verificar
rmp sprint get 1
# Deve mostrar tasks: [1, 2]
```

---

### Tarefa 8: Corrigir Parser de Flags Longas (Prioridade Alta) ✅ CONCLUÍDO

**Descrição Técnica:**
O parser de argumentos em `handleTaskAdd` verificava `"--expected"` em vez de `"--expected-result"` como documentado na SPEC.

**Implementação:**
1. Corrigido `src/cli.zig`, função `handleTaskAdd`:
   - Alterado `std.mem.eql(u8, arg, "--expected")` para `std.mem.eql(u8, arg, "--expected-result")`
2. Corrigido `src/cli.zig`, função `handleTaskEdit`:
   - Alterado `std.mem.eql(u8, arg, "--expected")` para `std.mem.eql(u8, arg, "--expected-result")`

**Status:** ✅ Concluído em 2026-03-14
- Flag `--expected-result` funciona corretamente
- Todas as flags longas mapeadas conforme SPEC:
  - `--description` ✅
  - `--action` ✅
  - `--expected-result` ✅
  - `--priority` ✅
  - `--severity` ✅
  - `--specialists` ✅

**Validação:**
```bash
rmp task create --description "Test" --action "Action" --expected-result "Result"
# ✅ Cria task com sucesso
```

---

### Tarefa 9: Implementar `sprint rm-tasks` (Prioridade Média)

**Descrição Técnica:**
A SPEC (COMMANDS.md:201) documenta `rmp sprint rm-tasks` para remover múltiplas tasks de um sprint, mas apenas existe `rm-task` (singular) que remove uma única task.

**Implementação Requerida:**
1. Em `src/cli.zig`, na função `handleSprintCommand`:
   - Adicionar handler para `"rm-tasks"` (além do existente `"rm-task"`)
   - Aceitar argumentos: `<sprint-id> <task-ids>`
   - Usar `parseIds()` para processar lista de IDs
   - Chamar `queries.removeTaskFromSprint()` para cada task
   - Atualizar status das tasks para `BACKLOG`
   - Logar operação `SPRINT_REMOVE_TASK` no audit

**Validação:**
```bash
rmp sprint add 1 1,2,3  # Adicionar tasks 1, 2, 3 ao sprint 1
rmp sprint rm-tasks 1 2,3  # Remover tasks 2 e 3
rmp sprint get 1
# Deve mostrar apenas task 1 no sprint
```

---

### Tarefa 10: Implementar `sprint mv-tasks` (Prioridade Média)

**Descrição Técnica:**
A SPEC (COMMANDS.md:202) documenta `rmp sprint mv-tasks` para mover tasks entre sprints, mas este comando não está implementado.

**Implementação Requerida:**
1. Em `src/cli.zig`, na função `handleSprintCommand`:
   - Adicionar handler para `"mv-tasks"`
   - Aceitar argumentos: `<from-sprint-id> <to-sprint-id> <task-ids>`
   - Verificar se todas as tasks existem no sprint de origem
   - Chamar `queries.moveTaskBetweenSprints()` para cada task
   - Logar operação `SPRINT_MOVE_TASK` no audit

**Validação:**
```bash
rmp sprint create "Sprint 1"  # ID 1
rmp sprint create "Sprint 2"  # ID 2
rmp task add -d "Task" -a "Action" -e "Result"  # ID 1
rmp sprint add 1 1  # Adicionar task 1 ao sprint 1
rmp sprint mv-tasks 1 2 1  # Mover task 1 do sprint 1 para sprint 2
rmp sprint get 2
# Deve mostrar task 1 no sprint 2
```

---

### Tarefa 11: Implementar `audit history` com Filtros (Prioridade Média)

**Descrição Técnica:**
A SPEC documenta comandos de histórico (`audit history --task <id>` e `audit history --sprint <id>`), mas estes não estão implementados ou não funcionam conforme esperado.

**Implementação Requerida:**
1. Em `src/cli.zig`, na função `handleAuditCommand`:
   - Adicionar handler para `"history"` ou `"hist"`
   - Suportar flags:
     - `--task <id>`: Filtrar por task específica
     - `--sprint <id>`: Filtrar por sprint específica
     - `--operation <op>`: Filtrar por tipo de operação
     - `--since <date>`: Filtrar desde data
     - `--until <date>`: Filtrar até data
2. Em `src/db/queries.zig`:
   - Adicionar query parametrizada para filtrar audit por entidade e/ou operação

**Validação:**
```bash
rmp audit history --task 1
# Deve retornar apenas entradas de audit para task 1

rmp audit history --sprint 1
# Deve retornar apenas entradas de audit para sprint 1

rmp audit history --operation TASK_STATUS_CHANGE
# Deve retornar apenas mudanças de status
```

---

### Tarefa 12: Padronizar Respostas de Criação (Prioridade Baixa)

**Descrição Técnica:**
A SPEC (DATA_FORMATS.md:54) indica que criação deve retornar `{"id": 42}`, mas roadmaps retornam `{"name": "project1"}`. Isto é aceitável dado que roadmaps são identificados por nome, mas deve ser documentado.

**Implementação Requerida:**
1. Verificar se a resposta atual `{"name": "..."}` para roadmaps é intencional
2. Se sim, atualizar a SPEC para refletir este comportamento
3. Se não, modificar `src/commands/roadmap.zig:135` para retornar `{"id": ...}` (embora roadmaps não tenham ID numérico)

**Validação:**
```bash
rmp roadmap create test-standard
# Deve retornar consistentemente (decidir entre {"name": "test-standard"} ou outro formato)
```

---

### Tarefa 13: Revisar Exit Codes (Prioridade Baixa)

**Descrição Técnica:**
Alguns comandos podem estar a retornar exit code 0 mesmo quando há erros JSON no output, ou a usar códigos inconsistentes com a SPEC (DATA_FORMATS.md:76-88).

**Implementação Requerida:**
1. Revisar todos os handlers em `src/cli.zig` para garantir:
   - Exit code 0 apenas em sucesso real
   - Exit code 2 (MISUSE) para input inválido
   - Exit code 4 (NOT_FOUND) para recursos não encontrados
   - Exit code 5 (EXISTS) para recursos duplicados
2. Verificar se `std.process.exit()` está sendo chamado com o código correto em todos os caminhos de erro

**Validação:**
```bash
rmp task get 99999; echo "Exit: $?"
# Deve retornar Exit: 4

rmp roadmap create existing; rmp roadmap create existing; echo "Exit: $?"
# Deve retornar Exit: 5

rmp invalidcommand; echo "Exit: $?"
# Deve retornar Exit: 2 ou 127
```

---

### Tarefa 14: Correção de Comandos que Retornam JSON em Erros (exit code != 0) 🔄 PARCIALMENTE CONCLUÍDO

**Descrição Técnica:**
Conforme a SPEC (COMMANDS.md:15-34), erros devem seguir o comportamento típico de CLI: mensagens em texto simples (human-readable) escritas para o stderr. No entanto, os testes exaustivos identificaram 27 comandos que retornam JSON formatado em erros, o que viola a especificação.

**Status:** 🔄 Parcialmente Concluído em 2026-03-14
- ✅ Infraestrutura implementada em `src/cli.zig`:
  - `printError()` - exibe mensagens de erro em texto simples no stderr
  - `printErrorWithHelp()` - exibe erro seguido de help do comando
  - `printErrorWithSubcommandHelp()` - exibe erro seguido de help específico do subcomando
- ✅ Exit codes implementados conforme SPEC
- ✅ Help em formato texto implementado para todos os níveis (global, comando, subcomando)
- ✅ Handlers de CLI atualizados para usar texto simples em erros de input
- ⏸️ PENDENTE: Converter erros JSON para texto simples nos ficheiros:
  - `src/commands/roadmap.zig` (createRoadmap, removeRoadmap, useRoadmap)
  - `src/commands/task.zig` (getTask, changeTaskStatus, setPriority, setSeverity, deleteTask)
  - `src/commands/sprint.zig` (addSprint, addTaskToSprint)
  - `src/commands/audit.zig` (listAuditEntries, getAuditStats)

**Comandos Identificados que Retornam JSON em Erros:**

#### Roadmap Commands
| Comando | Código JSON Atual | Exit Code | Correção Necessária |
|---------|-------------------|-----------|---------------------|
| `roadmap create <nome inválido>` | `{"code":"INVALID_INPUT",...}` | 5 | Texto simples no stderr |
| `roadmap remove <inexistente>` | `{"code":"ROADMAP_NOT_FOUND",...}` | 4 | Texto simples no stderr |
| `roadmap use <inexistente>` | `{"code":"ROADMAP_NOT_FOUND",...}` | 4 | Texto simples no stderr |
| `roadmap create <existente>` | `{"code":"ROADMAP_EXISTS",...}` | 5 | Texto simples no stderr |

#### Task Commands (sem roadmap selecionada)
| Comando | Código JSON Atual | Exit Code | Correção Necessária |
|---------|-------------------|-----------|---------------------|
| `task get 1` | `{"code":"TASK_NOT_FOUND",...}` | 4 | Texto simples no stderr |
| `task stat 1 DOING` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task prio 1 5` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task sev 1 5` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task delete 1` | `{"code":"DELETE_FAILED",...}` | 4 | Texto simples no stderr |

#### Task Commands (com roadmap, dados inválidos)
| Comando | Código JSON Atual | Exit Code | Correção Necessária |
|---------|-------------------|-----------|---------------------|
| `task get 99999` | `{"code":"TASK_NOT_FOUND",...}` | 4 | Texto simples no stderr |
| `task stat 99999 DOING` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task prio 99999 5` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task prio 1 10` | `{"code":"INVALID_PRIORITY",...}` | 6 | Texto simples no stderr |
| `task prio 1 -1` | `{"code":"INVALID_PRIORITY",...}` | 6 | Texto simples no stderr |
| `task sev 99999 5` | `{"code":"UPDATE_FAILED",...}` | 4 | Texto simples no stderr |
| `task sev 1 10` | `{"code":"INVALID_SEVERITY",...}` | 6 | Texto simples no stderr |
| `task delete 99999` | `{"code":"DELETE_FAILED",...}` | 4 | Texto simples no stderr |

#### Sprint Commands
| Comando | Código JSON Atual | Exit Code | Correção Necessária |
|---------|-------------------|-----------|---------------------|
| `sprint add 1 1` (sem roadmap) | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |
| `sprint add 99999 1` | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |
| `sprint add 1 99999` | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |

#### Audit Commands
| Comando | Código JSON Atual | Exit Code | Correção Necessária |
|---------|-------------------|-----------|---------------------|
| `audit list` (sem roadmap) | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |
| `audit stats` (sem roadmap) | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |
| `audit stats --since invalid` | `{"code":"DB_ERROR",...}` | 1 | Texto simples no stderr |
| `audit stats --since 2025-01-01 --until 2024-01-01` | `{"code":"INVALID_DATE_RANGE",...}` | 1 | Texto simples no stderr |

**Implementação Requerida:**

1. **Em `src/commands/roadmap.zig`:**
   - Modificar `createRoadmap` (linha 82-139): Substituir chamadas a `json.errorResponse()` e `json.errorResponseWithDetails()` por `printError()` e `printErrorWithHelp()`
   - Modificar `removeRoadmap` (linha 142-180): Substituir `json.errorResponse()` por mensagens em texto simples
   - Modificar `useRoadmap` (linha 183-229): Substituir `json.errorResponse()` por mensagens em texto simples

2. **Em `src/commands/task.zig`:**
   - Modificar `getTask` (linha 99-127): Substituir `json.errorResponseWithDetails()` por texto simples
   - Modificar `changeTaskStatus` (linha 130-239): Substituir todas as chamadas `json.errorResponse()` por texto simples
   - Modificar `setPriority` (linha 242-326): Substituir todas as chamadas `json.errorResponse()` por texto simples
   - Modificar `setSeverity` (linha 329-413): Substituir todas as chamadas `json.errorResponse()` por texto simples
   - Modificar `deleteTask` (linha 446-530): Substituir todas as chamadas `json.errorResponse()` por texto simples

3. **Em `src/commands/sprint.zig`:**
   - Modificar `addSprint` (linha 12-55): Substituir `json.errorResponse()` por texto simples
   - Modificar `addTaskToSprint` (linha 244-310): Substituir `json.errorResponse()` por texto simples

4. **Em `src/commands/audit.zig`:**
   - Modificar `listAuditEntries` (linha 24-115): Substituir `json.errorResponse()` por texto simples
   - Modificar `getAuditStats` (linha 199-338): Substituir `json.errorResponse()` por texto simples

**Exemplo de Correção:**

Antes:
```zig
return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Roadmap not found");
```

Depois:
```zig
printError("Roadmap not found");
return ExitCode.NOT_FOUND;
```

**Validação:**
```bash
# Testar comandos que anteriormente retornavam JSON em erros
rmp roadmap create "invalid name" 2>&1 | grep -q "^{" && echo "FAIL: Ainda retorna JSON" || echo "PASS: Retorna texto simples"
rmp roadmap remove nonexistent 2>&1 | grep -q "^{" && echo "FAIL: Ainda retorna JSON" || echo "PASS: Retorna texto simples"
rmp task get 99999 2>&1 | grep -q "^{" && echo "FAIL: Ainda retorna JSON" || echo "PASS: Retorna texto simples"
rmp task prio 1 10 2>&1 | grep -q "^{" && echo "FAIL: Ainda retorna JSON" || echo "PASS: Retorna texto simples"
rmp audit stats 2>&1 | grep -q "^{" && echo "FAIL: Ainda retorna JSON" || echo "PASS: Retorna texto simples"
```

**Resumo das Alterações Necessárias:**

| Ficheiro | Funções a Modificar | Tipo de Alteração |
|----------|---------------------|-------------------|
| `src/commands/roadmap.zig` | `createRoadmap`, `removeRoadmap`, `useRoadmap` | JSON → Texto simples |
| `src/commands/task.zig` | `getTask`, `changeTaskStatus`, `setPriority`, `setSeverity`, `deleteTask` | JSON → Texto simples |
| `src/commands/sprint.zig` | `addSprint`, `addTaskToSprint` | JSON → Texto simples |
| `src/commands/audit.zig` | `listAuditEntries`, `getAuditStats` | JSON → Texto simples |

**Nota Importante:** Os comandos que atualmente retornam JSON em erros devem ser migrados para usar as funções utilitárias de output em texto simples já existentes em `src/cli.zig` (`printError`, `printErrorWithHelp`) ou criar equivalentes se necessário.

---

## Ficheiros Críticos
- `src/cli.zig`: Ponto central de controlo de output e despacho de comandos.
- `src/utils/json.zig`: Camada de serialização e resposta.
- `src/utils/time.zig`: Utilitário de formatação temporal.
- `src/commands/*.zig`: Lógica individual de cada módulo (task, roadmap, sprint, audit).

## Tarefas Adicionais Identificadas em Testes Exaustivos

### Prioridade Crítica

#### T5. Correção de Memory Leaks
**Descrição Técnica:**
O General Purpose Allocator (GPA) do Zig detectou vazamentos de memória em múltiplas operações. O padrão comum é alocação de strings formatadas via `std.fmt.allocPrint` que não são libertadas antes de retornar ou antes de chamar `std.process.exit()`.

**Locais identificados:**
- `src/commands/task.zig:152` - `changeTaskStatus` (quando `existing_ids.len == 0`)
- `src/commands/task.zig:264` - `setPriority` (quando tasks não encontradas)
- `src/commands/task.zig:351` - `setSeverity` (quando tasks não encontradas)
- `src/commands/sprint.zig:121` - `openSprint` (sucesso, `response` alocado mas não libertado antes do return)
- `src/commands/sprint.zig:190` - `closeSprint` (sucesso)
- `src/commands/sprint.zig:501` - `reopenSprint` (sucesso)

**Implementação:**
- Usar `defer allocator.free()` imediatamente após cada alocação
- Em caminhos de erro que chamam `std.process.exit()`, garantir libertação antes do exit ou usar `defer` logo após a alocação
- Revisar todas as funções em `src/commands/*.zig` que retornam JSON formatado

**Validação:**
```bash
# Executar com GPA em modo debug
zig build run -- task stat 99999 SPRINT 2>&1 | grep -q "leaked" && echo "FAIL" || echo "PASS"
zig build run -- sprint start 1 2>&1 | grep -q "leaked" && echo "FAIL" || echo "PASS"
```
Não deve haver mensagens "memory address X leaked" no stderr.

---

#### T6. Adicionar Alias `task create` ✅ CONCLUÍDO
**Descrição Técnica:**
A SPEC (COMMANDS.md:125) documenta `task create` como comando para criar tasks, mas a implementação atual só reconhece `task add` e `task new` (cli.zig:309).

**Implementação:**
Em `src/cli.zig`, modificado handler de task para aceitar "create" como alias:
```zig
} else if (std.mem.eql(u8, subcmd, "create") or std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {
```

**Status:** ✅ Concluído em 2026-03-14
- Alias `task create` implementado e funcional
- Help específico para `task create` adicionado
- Testado e validado

---

#### T7. Separar Comando `sprint create` de `sprint add` 🔄 PARCIALMENTE CONCLUÍDO
**Descrição Técnica:**
Atualmente `sprint add` é usado para criar sprints (recebendo descrição como argumentos posicionais), o que contradiz a SPEC que define `sprint add` para adicionar tasks a sprints existentes.

**Status:** 🔄 Parcialmente Concluído em 2026-03-14
- ✅ `sprint create` funciona como alias de `sprint add` (criação de sprints)
- ✅ `sprint new` também funciona como alias
- ⏸️ PENDENTE: Separar `sprint add` para adicionar tasks a sprints existentes (atualmente `add-tasks` faz esta função)

**Implementação:**
1. Em `src/cli.zig`, criar novo handler `handleSprintCreate` para criar sprints
2. Modificar `handleSprintCommand` para distinguir:
   - `sprint create <description>` - Cria sprint
   - `sprint add <sprint-id> <task-ids>` - Adiciona tasks a sprint
3. Atualizar `src/commands/sprint.zig` para implementar `addTaskToSprint` corretamente

**Validação:**
```bash
rmp sprint create "Sprint 1 Description"  # Deve criar sprint
rmp sprint add 1 1,2,3  # Deve adicionar tasks 1,2,3 ao sprint 1
rmp sprint get 1  # Deve mostrar tasks [1,2,3]
```

---

#### T8. Corrigir Parser de Flags Longas
**Descrição Técnica:**
O parser em `handleTaskAdd` (cli.zig:504-535) verifica `--expected` mas a SPEC documenta `--expected-result`. Flags longas como `--description`, `--action` não estão a ser reconhecidas corretamente.

**Implementação:**
Em `src/cli.zig`, função `handleTaskAdd`:
- Linha 528: Mudar `"--expected"` para `"--expected-result"`
- Verificar se o parser de flags está a consumir corretamente os argumentos seguintes
- Adicionar teste para garantir que `--description "text"` funcione igual a `-d "text"`

**Validação:**
```bash
rmp task add --description "Test desc" --action "Test action" --expected-result "Test result"
# Deve criar task com sucesso, retornando {"id": N}
```

---

#### T9. Implementar `sprint rm-tasks` (Bulk Removal) ✅ CONCLUÍDO
**Descrição Técnica:**
A SPEC (COMMANDS.md:201) define `sprint rm-tasks` para remover múltiplas tasks de um sprint, mas só existe `rm-task` (singular) que remove uma única task.

**Status:** ✅ Concluído em 2026-03-14
- ✅ Handler para `rm-tasks` implementado em `src/cli.zig:946`
- ✅ Aceita formato: `rmp sprint rm-tasks <sprint-id> <task-ids>`
- ✅ Também suporta aliases: `remove-task`, `remove-tasks`
- ✅ Processa múltiplos IDs via `parseIds()`

**Implementação:**
Em `src/cli.zig`, linha 946:
```zig
} else if (std.mem.eql(u8, subcmd, "remove-task") or std.mem.eql(u8, subcmd, "remove-tasks") or std.mem.eql(u8, subcmd, "rm-tasks")) {
```

**Validação:**
```bash
rmp sprint add 1 1,2,3,4,5  # Adicionar tasks
rmp sprint rm-tasks 1 2,3   # Remover tasks 2 e 3
rmp sprint tasks 1          # Deve mostrar apenas [1,4,5]
```

---

#### T10. Implementar `sprint mv-tasks` ✅ CONCLUÍDO
**Descrição Técnica:**
A SPEC (COMMANDS.md:202) define `sprint mv-tasks` para mover tasks entre sprints.

**Status:** ✅ Concluído em 2026-03-14
- ✅ Handler para `mv-tasks`/`move-tasks` implementado em `src/cli.zig:985`
- ✅ Aceita formato: `rmp sprint mv-tasks <from-sprint-id> <to-sprint-id> <task-ids>`
- ✅ Usa `sprint.moveTaskBetweenSprints()` para mover tasks
- ✅ Help específico implementado

**Implementação:**
Em `src/cli.zig`, linha 985:
```zig
} else if (std.mem.eql(u8, subcmd, "move-tasks") or std.mem.eql(u8, subcmd, "mv-tasks")) {
    // Spec: mv-tasks <from-sprint> <to-sprint> <task-ids...>
    // Parse from_sprint, to_sprint, and task_ids
    // Call sprint.moveTaskBetweenSprints() for each task
```

**Validação:**
```bash
rmp sprint add 1 1,2,3
rmp sprint add 2 4,5
rmp sprint mv-tasks 1 2 2,3  # Mover tasks 2,3 do sprint 1 para 2
rmp sprint tasks 1  # Deve mostrar [1]
rmp sprint tasks 2  # Deve mostrar [4,5,2,3]
```

---

### Prioridade Alta

#### T11. Corrigir Formato de Resposta de Criação de Roadmap ✅ CONCLUÍDO
**Descrição Técnica:**
A SPEC (DATA_FORMATS.md:54) define que criação retorna `{"id": 42}`, mas roadmaps retornam `{"name": "project1"}`.

**Status:** ✅ Concluído em 2026-03-15
- ✅ A SPEC foi atualizada para documentar o comportamento específico de roadmaps
- ✅ Linha 54 em DATA_FORMATS.md: `{"id": 42}` (ou `{"name": "project1"}` for roadmaps)
- ✅ Comportamento é intencional: roadmaps são identificados por nome, não por ID numérico

**Decisão:** A SPEC foi atualizada para refletir `{"name": ...}` para roadmaps, mantendo `{"id": ...}` para tasks e sprints.

**Validação:**
```bash
rmp roadmap create new-project
# Retorna: {"name": "new-project"} ✅
```

---

#### T12. Revisar Exit Codes ✅ CONCLUÍDO
**Descrição Técnica:**
Alguns comandos retornam exit code 0 mesmo quando há erros JSON no output. A SPEC (DATA_FORMATS.md:76-88) define códigos específicos.

**Implementação:**
Implementado em `src/cli.zig`:
- Exit code 0 apenas em sucesso sem erros
- Exit code 2 (MISUSE) para input inválido
- Exit code 4 (NOT_FOUND) para recursos inexistentes
- Exit code 5 (EXISTS) para duplicados
- Exit code 127 (CMD_NOT_FOUND) para comandos desconhecidos

**Status:** ✅ Concluído em 2026-03-14
- Exit codes implementados conforme SPEC
- Função `getExitCodeForError` mapeia códigos de erro para exit codes
- Todos os handlers atualizados para usar exit codes corretos

**Validação:**
```bash
rmp task get 99999; echo $?  # Retorna 4 ✅
rmp roadmap create existing; echo $?  # Retorna 5 ✅
rmp invalidcmd; echo $?  # Retorna 127 ✅
```

---

#### T13. Implementar `audit history` com Filtros ✅ CONCLUÍDO
**Descrição Técnica:**
A SPEC menciona `audit history` com filtros `--task` e `--sprint`, mas a implementação está incompleta.

**Status:** ✅ Concluído em 2026-03-14
- ✅ Handler para `history`/`hist` implementado em `src/cli.zig:1165`
- ✅ Suporta flags: `-e/--entity-type` (TASK/SPRINT), `--entity-id`
- ✅ Suporta filtro global `-r/--roadmap`
- ✅ Implementa `audit.getEntityHistory()` para obter histórico

**Implementação:**
Em `src/cli.zig`, linha 1165-1227:
```zig
} else if (std.mem.eql(u8, subcmd, "history") or std.mem.eql(u8, subcmd, "hist")) {
    // Parse flags for history command
    var entity_type: ?[]const u8 = null;
    var entity_id: ?i64 = null;
    // ... parsing de argumentos e chamada a audit.getEntityHistory()
```

**Validação:**
```bash
rmp audit history --entity-type TASK 1          # Histórico da task 1
rmp audit history --entity-type SPRINT 1          # Histórico do sprint 1
rmp audit list --operation TASK_STATUS_CHANGE     # Filtrar por operação
```

---

#### T14. Melhorar Mensagens de Erro de Transição de Status
**Descrição Técnica:**
Quando se tenta transicionar de COMPLETED para outro status, a mensagem de erro não é clara sobre a regra de negócio.

**Implementação:**
Em `src/commands/task.zig`, função `changeTaskStatus`, melhorar a mensagem:
```zig
return json.errorResponse(allocator, "INVALID_STATUS_TRANSITION",
    "Task is COMPLETED and cannot change status. Create a new task instead.");
```

**Validação:**
```bash
rmp task stat 1 COMPLETED  # Completa task 1
rmp task stat 1 BACKLOG    # Deve mostrar mensagem clara sobre impossibilidade
```

---

#### T15. Correção de Comandos que Retornam JSON em Erros
**Descrição Técnica:**
Conforme a SPEC, erros devem ser em texto simples no stderr, mas 27 comandos identificados nos testes exaustivos retornam JSON em erros (exit code != 0).

**Comandos Afetados:**
- Roadmap: `create` (nome inválido/existente), `remove` (inexistente), `use` (inexistente)
- Task: `get` (não encontrada), `stat` (falha), `prio` (falha/inválido), `sev` (falha/inválido), `delete` (não encontrada)
- Sprint: `add` (sem roadmap, IDs inválidos)
- Audit: `list` (sem roadmap), `stats` (sem roadmap, datas inválidas)

**Implementação:**
1. Substituir `json.errorResponse()` e `json.errorResponseWithDetails()` por `printError()` em todos os comandos afetados
2. Garantir que mensagens de erro sejam texto simples human-readable
3. Manter exit codes conforme especificação (2, 4, 5, 6)

**Ficheiros a Modificar:**
- `src/commands/roadmap.zig`: `createRoadmap`, `removeRoadmap`, `useRoadmap`
- `src/commands/task.zig`: `getTask`, `changeTaskStatus`, `setPriority`, `setSeverity`, `deleteTask`
- `src/commands/sprint.zig`: `addSprint`, `addTaskToSprint`
- `src/commands/audit.zig`: `listAuditEntries`, `getAuditStats`

**Validação:**
```bash
# Nenhum comando deve retornar JSON em erros
rmp roadmap create "invalid" 2>&1 | grep -q "^{" && echo "FAIL" || echo "PASS"
rmp task get 99999 2>&1 | grep -q "^{" && echo "FAIL" || echo "PASS"
rmp audit stats 2>&1 | grep -q "^{" && echo "FAIL" || echo "PASS"
```

---

### Prioridade Média

#### T16. Adicionar Validação de XSS
**Descrição Técnica:**
Embora o JSON escaping previna XSS em output, campos de texto devem ser sanitizados no input.

**Implementação:**
Em `src/utils/text.zig`, criar função `sanitizeInput` que remove ou escapa:
- Tags HTML: `<script>`, `<iframe>`, etc.
- Event handlers: `onclick=`, `onerror=`, etc.
- Chamar em todos os campos de texto antes de inserir na DB

**Validação:**
```bash
rmp task add -d "<script>alert('xss')</script>" -a "Action" -e "Result"
rmp task get 1  # Deve mostrar descrição sanitizada (sem tags script)
```

---

#### T17. Implementar `sprint update` Completo 🔄 PARCIALMENTE CONCLUÍDO
**Descrição Técnica:**
O comando `sprint update` existe mas só suporta atualização de descrição. Deve suportar outros campos conforme necessário.

**Status:** 🔄 Parcialmente Concluído em 2026-03-14
- ✅ Comando `sprint update` implementado em `src/cli.zig:889`
- ✅ Alias `sprint upd` implementado
- ✅ Atualização de descrição funcional
- ⏸️ PENDENTE: Suporte a atualização de outros campos (status, datas)

**Implementação:**
Em `src/cli.zig`, linha 889:
```zig
} else if (std.mem.eql(u8, subcmd, "update") or std.mem.eql(u8, subcmd, "upd")) {
```

**Validação:**
```bash
rmp sprint update 1 --description "New description"
rmp sprint upd 1 "New description"  # Usando alias
rmp sprint get 1  # Deve refletir mudanças
```

---

#### T18. Adicionar Paginação a Listagens ✅ CONCLUÍDO
**Descrição Técnica:**
Listagens grandes (task list, audit list) podem retornar muitos dados.

**Status:** ✅ Concluído em 2026-03-14
- ✅ Flags `--limit` / `-l` implementadas em `src/cli.zig:1128,1346`
- ✅ Flag `--offset` implementada em `src/cli.zig:1140`
- ✅ Suporte em `audit list` com `AuditListOptions`
- ✅ Validação de limites (1-1000) e offset não-negativo

**Implementação:**
Em `src/cli.zig`:
```zig
// Para audit list
} else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--limit")) {
    options.limit = std.fmt.parseInt(i32, subargs[i], 10) catch { ... };
} else if (std.mem.eql(u8, arg, "--offset")) {
    options.offset = std.fmt.parseInt(i32, subargs[i], 10) catch { ... };
}
```

**Validação:**
```bash
rmp task list --limit 10 --offset 20  # Retorna tasks 21-30
rmp audit list --limit 50 --offset 0  # Primeiros 50 resultados
```

---

## Plano de Validação Completo

### Testes Unitários
```bash
zig build test
```

### Testes de Integração
```bash
# Setup
rm -rf /tmp/rmp_test && mkdir -p /tmp/rmp_test/.roadmaps
export HOME=/tmp/rmp_test

# Testar todos os comandos críticos
./zig-out/aarch64-macos/bin/rmp roadmap create test-project
./zig-out/aarch64-macos/bin/rmp roadmap use test-project
./zig-out/aarch64-macos/bin/rmp task create -d "Test" -a "Action" -e "Result"
./zig-out/aarch64-macos/bin/rmp sprint create "Sprint 1"
./zig-out/aarch64-macos/bin/rmp sprint add 1 1
./zig-out/aarch64-macos/bin/rmp sprint rm-tasks 1 1

# Verificar memory leaks
# (executar com debug allocator e verificar stderr)
```

### Validação de Conformidade com SPEC
- [ ] Todos os comandos da SPEC existem e funcionam
- [ ] Todos os aliases funcionam
- [ ] Formatos de output JSON estão corretos
- [ ] Exit codes estão corretos
- [ ] Não há memory leaks em operações comuns
- [ ] Tratamento de erros é robusto

---

## Plano de Validação Detalhado das Novas Tarefas

### Script de Validação Completo

Criar ficheiro `validate_implementation.sh`:

```bash
#!/bin/bash
# validate_implementation.sh - Validação completa das correções

set -e
RMP="./zig-out/aarch64-macos/bin/rmp"
TEST_DIR="/tmp/rmp_validation_$$"
FAILED=0
PASSED=0

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR/.roadmaps"
    export HOME="$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

# ============================================
# T5: Memory Leaks
# ============================================
echo ""
echo "=== T5: Validação de Memory Leaks ==="

setup
$RMP roadmap create leak-test && $RMP roadmap use leak-test
$RMP task add -d "Test" -a "Action" -e "Result"

# Testar operações que causavam leaks
output=$(($RMP task stat 99999 SPRINT 2>&1) || true)
if echo "$output" | grep -q "leaked"; then
    fail "Memory leak em task stat"
else
    pass "Sem memory leak em task stat"
fi

output=$(($RMP task prio 99999 5 2>&1) || true)
if echo "$output" | grep -q "leaked"; then
    fail "Memory leak em task prio"
else
    pass "Sem memory leak em task prio"
fi

output=$(($RMP sprint start 99999 2>&1) || true)
if echo "$output" | grep -q "leaked"; then
    fail "Memory leak em sprint start"
else
    pass "Sem memory leak em sprint start"
fi

teardown

# ============================================
# T6: task create alias
# ============================================
echo ""
echo "=== T6: Validação do Alias task create ==="

setup
$RMP roadmap create create-test && $RMP roadmap use create-test

if $RMP task create --description "Test" --action "Action" --expected-result "Result" >/dev/null 2>&1; then
    pass "task create funciona como alias"
else
    fail "task create não funciona"
fi

teardown

# ============================================
# T7: sprint create vs add
# ============================================
echo ""
echo "=== T7: Validação sprint create/add ==="

setup
$RMP roadmap create sprint-test && $RMP roadmap use sprint-test

# Criar sprint
if output=$($RMP sprint create "Sprint Test" 2>&1) && echo "$output" | grep -q '"id":'; then
    pass "sprint create funciona"
else
    fail "sprint create não funciona"
fi

# Criar tasks
$RMP task add -d "T1" -a "A" -e "R"
$RMP task add -d "T2" -a "A" -e "R"

# Adicionar tasks ao sprint
if $RMP sprint add 1 1,2 >/dev/null 2>&1; then
    pass "sprint add funciona para adicionar tasks"
else
    fail "sprint add não funciona"
fi

# Verificar
if $RMP sprint get 1 2>&1 | grep -q '"tasks":\[1,2\]'; then
    pass "Tasks adicionadas corretamente ao sprint"
else
    fail "Tasks não adicionadas corretamente"
fi

teardown

# ============================================
# T8: Flags longas
# ============================================
echo ""
echo "=== T8: Validação de Flags Longas ==="

setup
$RMP roadmap create flags-test && $RMP roadmap use flags-test

if $RMP task add --description "Test" --action "Action" --expected-result "Result" >/dev/null 2>&1; then
    pass "Flags longas funcionam"
else
    fail "Flags longas não funcionam"
fi

teardown

# ============================================
# T9: sprint rm-tasks
# ============================================
echo ""
echo "=== T9: Validação sprint rm-tasks ==="

setup
$RMP roadmap create rm-test && $RMP roadmap use rm-test
$RMP sprint create "Sprint"
$RMP task add -d "T1" -a "A" -e "R"
$RMP task add -d "T2" -a "A" -e "R"
$RMP sprint add 1 1,2

if $RMP sprint rm-tasks 1 2 >/dev/null 2>&1; then
    pass "sprint rm-tasks funciona"
else
    fail "sprint rm-tasks não funciona"
fi

if $RMP sprint get 1 2>&1 | grep -q '"tasks":\[1\]'; then
    pass "Task removida corretamente"
else
    fail "Task não removida corretamente"
fi

teardown

# ============================================
# T10: sprint mv-tasks
# ============================================
echo ""
echo "=== T10: Validação sprint mv-tasks ==="

setup
$RMP roadmap create mv-test && $RMP roadmap use mv-test
$RMP sprint create "Sprint 1"
$RMP sprint create "Sprint 2"
$RMP task add -d "Task" -a "Action" -e "Result"
$RMP sprint add 1 1

if $RMP sprint mv-tasks 1 2 1 >/dev/null 2>&1; then
    pass "sprint mv-tasks funciona"
else
    fail "sprint mv-tasks não funciona"
fi

teardown

# ============================================
# T12: Exit codes
# ============================================
echo ""
echo "=== T12: Validação de Exit Codes ==="

setup
$RMP roadmap create exit-test && $RMP roadmap use exit-test

# Testar NOT_FOUND (4)
$RMP task get 99999 >/dev/null 2>&1 || code=$?
if [ "${code:-0}" -eq 4 ]; then
    pass "Exit code 4 para NOT_FOUND"
else
    fail "Exit code incorreto para NOT_FOUND (esperado 4, got ${code:-0})"
fi

# Testar EXISTS (5)
$RMP roadmap create exit-test2
$RMP roadmap create exit-test2 >/dev/null 2>&1 || code=$?
if [ "${code:-0}" -eq 5 ]; then
    pass "Exit code 5 para EXISTS"
else
    fail "Exit code incorreto para EXISTS (esperado 5, got ${code:-0})"
fi

teardown

# ============================================
# Resumo
# ============================================
echo ""
echo "========================================"
echo "Resumo da Validação"
echo "========================================"
echo -e "${GREEN}Passaram:${NC} $PASSED"
echo -e "${RED}Falharam:${NC} $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Todas as validações passaram!${NC}"
    exit 0
else
    echo -e "${RED}Algumas validações falharam.${NC}"
    exit 1
fi
```

### Execução do Plano de Validação

```bash
# 1. Compilar o projeto
zig build

# 2. Executar testes unitários
zig build test

# 3. Executar validação completa
chmod +x validate_implementation.sh
./validate_implementation.sh

# 4. Verificar memory leaks específicos
export HOME=/tmp/leak_test
mkdir -p $HOME/.roadmaps
./zig-out/aarch64-macos/bin/rmp roadmap create leak && ./zig-out/aarch64-macos/bin/rmp roadmap use leak
./zig-out/aarch64-macos/bin/rmp task add -d "Test" -a "A" -e "R"
# Executar várias operações e verificar stderr por "leaked"
```
