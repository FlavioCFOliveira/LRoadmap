# LRoadmap Skill

Skill para Claude Code que habilita fluxos agentic de gestão de tarefas e sprints através da CLI LRoadmap (`rmp`).

## Visão Geral

Esta skill transforma o Claude Code num orquestrador especializado em coordenação de tarefas organizadas por sprints. O Claude passa a ter capacidade de:

- Gerir roadmaps, tarefas e sprints via comandos CLI
- Orquestrar fluxos de trabalho completos de desenvolvimento
- Coordenar transições de estado de tarefas com validação
- Analisar progresso e estatísticas de sprints
- Manter audit trail completo de todas as operações

## Requisitos

- LRoadmap instalado e disponível no PATH como `rmp`
- Diretório `~/.roadmaps/` acessível para armazenamento de roadmaps
- Zig runtime (para build, se necessário)

## Instalação

### 1. Instalar LRoadmap

```bash
# Clone do repositório
git clone <repository-url>
cd LRoadmap

# Build com Zig
zig build

# Instalar binário
zig build install

# Verificar instalação
rmp --version
```

### 2. Configurar a Skill no Claude Code

Adicione a referência à skill no seu projeto:

```json
{
  "skills": [
    {
      "name": "lroadmap",
      "description": "Orquestração de tarefas e sprints via LRoadmap CLI",
      "file": "SKILL.md"
    }
  ]
}
```

Ou através do comando:

```bash
/skill lroadmap
```

## Modos de Operação

A skill opera em três modos principais:

### Modo 1: Orquestrador de Sprint (Padrão)

O Claude atua como coordenador de sprint, gerindo o fluxo completo de tarefas desde o backlog até à conclusão.

**Capacidades:**
- Criar e configurar sprints
- Adicionar tarefas ao sprint com priorização
- Monitorar progresso em tempo real
- Coordenar transições de estado
- Gerar relatórios de conclusão

**Comando de ativação:**
```
Atuar como orquestrador de sprint para o roadmap <nome>
```

### Modo 2: Gestor de Tarefas

Foco na criação e manutenção de tarefas individuais, independentemente de sprints.

**Capacidades:**
- Criar tarefas detalhadas com ação técnica e resultado esperado
- Ajustar prioridade e severidade
- Transicionar estados com validação
- Consultar histórico de alterações

**Comando de ativação:**
```
Gerir tarefas no roadmap <nome>
```

### Modo 3: Analista de Sprint

Análise de dados e estatísticas de sprints para tomada de decisões.

**Capacidades:**
- Estatísticas de conclusão
- Análise de audit trail
- Relatórios de produtividade
- Identificação de gargalos

**Comando de ativação:**
```
Analisar sprint <id> no roadmap <nome>
```

## Fluxos de Trabalho

### Fluxo 1: Ciclo Completo de Sprint

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   BACKLOG   │────▶│   SPRINT    │────▶│   DOING     │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  COMPLETED  │◀────│   TESTING   │◀────│   (work)    │
└─────────────┘     └─────────────┘     └─────────────┘
```

**Comandos do fluxo:**

```bash
# 1. Criar sprint
rmp sprint new -r <roadmap> -d "Sprint N - Descrição"

# 2. Criar tarefas no backlog
rmp task new -r <roadmap> -d "Descrição" -a "Ação técnica" -e "Resultado esperado" --priority 9 --severity 5

# 3. Adicionar tarefas ao sprint
rmp sprint add -r <roadmap> <sprint-id> <task-ids>

# 4. Iniciar sprint
rmp sprint start -r <roadmap> <sprint-id>

# 5. Durante o sprint - transicionar tarefas
rmp task stat -r <roadmap> <task-id> DOING
rmp task stat -r <roadmap> <task-id> TESTING
rmp task stat -r <roadmap> <task-id> COMPLETED

# 6. Estatísticas do sprint
rmp sprint stats -r <roadmap> <sprint-id>

# 7. Fechar sprint
rmp sprint close -r <roadmap> <sprint-id>
```

### Fluxo 2: Gestão de Prioridades

```bash
# Identificar tarefas de alta prioridade
rmp task ls -r <roadmap> -p 8

# Ajustar prioridade de múltiplas tarefas
rmp task prio -r <roadmap> <task-ids> <nova-prioridade>

# Ajustar severidade técnica
rmp task sev -r <roadmap> <task-ids> <nova-severidade>

# Listar sprint ordenado por prioridade/severidade
rmp sprint tasks -r <roadmap> <sprint-id>
```

### Fluxo 3: Análise e Auditoria

```bash
# Listar operações recentes
rmp audit ls -r <roadmap> -l 50

# Histórico de uma tarefa específica
rmp audit hist -r <roadmap> -e TASK <task-id>

# Estatísticas de audit
rmp audit stats -r <roadmap> --since <data>

# Sprint statistics
rmp sprint stats -r <roadmap> <sprint-id>
```

## Comandos CLI Disponíveis

### Roadmap Management

| Ação | Comando |
|------|---------|
| Listar roadmaps | `rmp roadmap list` / `rmp road ls` |
| Criar roadmap | `rmp roadmap new <nome>` / `rmp road new <nome>` |
| Remover roadmap | `rmp roadmap rm <nome>` / `rmp road rm <nome>` |
| Selecionar roadmap | `rmp roadmap use <nome>` / `rmp road use <nome>` |

### Task Management

| Ação | Comando |
|------|---------|
| Listar tarefas | `rmp task ls -r <roadmap> [-s <status>] [-p <min-priority>] [-l <limit>]` |
| Criar tarefa | `rmp task new -r <roadmap> -d <desc> -a <ação> -e <resultado> [-p <0-9>] [--severity <0-9>]` |
| Obter tarefa(s) | `rmp task get -r <roadmap> <id1,id2,id3>` |
| Alterar estado | `rmp task stat -r <roadmap> <id1,id2,id3> <BACKLOG/SPRINT/DOING/TESTING/COMPLETED>` |
| Alterar prioridade | `rmp task prio -r <roadmap> <id1,id2,id3> <0-9>` |
| Alterar severidade | `rmp task sev -r <roadmap> <id1,id2,id3> <0-9>` |
| Remover tarefa(s) | `rmp task rm -r <roadmap> <id1,id2,id3>` |

### Sprint Management

| Ação | Comando |
|------|---------|
| Listar sprints | `rmp sprint ls -r <roadmap> [-s <PENDING/OPEN/CLOSED>]` |
| Criar sprint | `rmp sprint new -r <roadmap> -d <descrição>` |
| Obter sprint | `rmp sprint get -r <roadmap> <id>` |
| Listar tarefas do sprint | `rmp sprint tasks -r <roadmap> <sprint-id> [-s <status>]` |
| Adicionar tarefas | `rmp sprint add -r <roadmap> <sprint-id> <task-ids>` |
| Remover tarefas | `rmp sprint rm-tasks -r <roadmap> <sprint-id> <task-ids>` |
| Mover tarefas | `rmp sprint mv-tasks -r <roadmap> <from> <to> <task-ids>` |
| Iniciar sprint | `rmp sprint start -r <roadmap> <sprint-id>` |
| Fechar sprint | `rmp sprint close -r <roadmap> <sprint-id>` |
| Reabrir sprint | `rmp sprint reopen -r <roadmap> <sprint-id>` |
| Atualizar sprint | `rmp sprint upd -r <roadmap> <sprint-id> -d <nova-desc>` |
| Estatísticas | `rmp sprint stats -r <roadmap> <sprint-id>` |
| Remover sprint | `rmp sprint rm -r <roadmap> <sprint-id>` |

### Audit Log

| Ação | Comando |
|------|---------|
| Listar audit | `rmp audit ls -r <roadmap> [-o <operation>] [-e <entity-type>] [--entity-id <id>] [--since <data>] [--until <data>] [-l <limit>]` |
| Histórico de entidade | `rmp audit hist -r <roadmap> -e <TASK/SPRINT> <id>` |
| Estatísticas de audit | `rmp audit stats -r <roadmap> [--since <data>] [--until <data>]` |

## Estados e Transições

### Estados de Tarefa

```
BACKLOG → SPRINT → DOING → TESTING → COMPLETED
   ↑                                    │
   └────────────────────────────────────┘ (reabrir)
```

### Estados de Sprint

```
PENDING → OPEN → CLOSED
            ↑      │
            └──────┘ (reopen)
```

## Convenções de Uso

### IDs Múltiplos (Bulk Operations)

Use vírgulas sem espaços para operações em lote:

```bash
rmp task stat -r project1 1,2,3,5 DOING
rmp task prio -r project1 10,11,12 9
rmp task rm -r project1 20,21,22
```

### Prioridade vs Severidade

- **Prioridade (0-9)**: Urgência/Pertinência (Product Owner)
  - 0 = baixa urgência
  - 9 = máxima urgência

- **Severidade (0-9)**: Impacto técnico (Dev Team)
  - 0 = impacto mínimo
  - 9 = impacto crítico

### Formato de Datas

ISO 8601 UTC: `YYYY-MM-DDTHH:mm:ss.sssZ`

Exemplo: `2026-03-12T14:30:00.000Z`

## Padrões de Interação

### Padrão 1: Criação Estruturada de Tarefas

Ao criar tarefas, o Claude deve:

1. **Descrição**: Objetivo claro e conciso
2. **Ação**: Passos técnicos específicos
3. **Resultado Esperado**: Critério de aceitação mensurável
4. **Prioridade**: Urgência para o negócio (0-9)
5. **Severidade**: Impacto técnico (0-9)

**Exemplo:**
```bash
rmp task new -r api-project \
  -d "Implementar autenticação JWT" \
  -a "Criar middleware de autenticação com verificação de tokens JWT" \
  -e "Endpoints protegidos retornam 401 sem token válido, 200 com token válido" \
  -p 9 \
  --severity 7
```

### Padrão 2: Transição de Estados com Validação

Antes de transicionar, o Claude deve:

1. Verificar estado atual da tarefa
2. Validar se a transição é permitida
3. Executar a mudança
4. Confirmar o novo estado

**Fluxo:**
```
Verificar estado → Validar transição → Executar → Confirmar
```

### Padrão 3: Relatórios de Progresso

O Claude pode gerar relatórios periódicos:

```bash
# Estatísticas do sprint atual
rmp sprint stats -r <roadmap> <sprint-id>

# Tarefas por estado
rmp task ls -r <roadmap> -s DOING
rmp task ls -r <roadmap> -s TESTING

# Audit das últimas operações
rmp audit ls -r <roadmap> -l 20
```

## Integração com Workflows Agentic

### Workflow: Desenvolvimento Guiado por Sprint

```
1. INÍCIO
   └── Verificar se há sprint ativo
       └── rmp sprint ls -r <roadmap> -s OPEN

2. PLANEAMENTO (se não houver sprint ativo)
   └── Criar novo sprint
   │   └── rmp sprint new -r <roadmap> -d "Sprint X"
   └── Identificar tarefas do backlog
   │   └── rmp task ls -r <roadmap> -s BACKLOG
   └── Adicionar tarefas ao sprint
       └── rmp sprint add -r <roadmap> <sprint-id> <task-ids>
   └── Iniciar sprint
       └── rmp sprint start -r <roadmap> <sprint-id>

3. EXECUÇÃO
   └── Listar tarefas do sprint
   │   └── rmp sprint tasks -r <roadmap> <sprint-id>
   └── Selecionar próxima tarefa (ordenada por prioridade/severidade)
   └── Transicionar para DOING
   │   └── rmp task stat -r <roadmap> <task-id> DOING
   └── [Executar trabalho técnico]
   └── Transicionar para TESTING
   │   └── rmp task stat -r <roadmap> <task-id> TESTING
   └── [Realizar testes]
   └── Transicionar para COMPLETED
       └── rmp task stat -r <roadmap> <task-id> COMPLETED

4. MONITORAMENTO
   └── Verificar estatísticas
   │   └── rmp sprint stats -r <roadmap> <sprint-id>
   └── Identificar tarefas bloqueadas
       └── rmp task ls -r <roadmap> -s DOING (antigas)

5. CONCLUSÃO (quando todas as tarefas completadas)
   └── Fechar sprint
       └── rmp sprint close -r <roadmap> <sprint-id>
   └── Gerar relatório final
       └── rmp audit stats -r <roadmap> --since <sprint-start>
```

### Workflow: Manutenção de Backlog

```
1. REVISÃO
   └── Listar todas as tarefas
   │   └── rmp task ls -r <roadmap>
   └── Identificar tarefas obsoletas
   └── Identificar tarefas mal priorizadas

2. ATUALIZAÇÃO
   └── Ajustar prioridades
   │   └── rmp task prio -r <roadmap> <ids> <nova-prioridade>
   └── Ajustar severidade
   │   └── rmp task sev -r <roadmap> <ids> <nova-severidade>
   └── Remover tarefas obsoletas
       └── rmp task rm -r <roadmap> <ids>

3. AUDITORIA
   └── Verificar histórico de alterações
       └── rmp audit ls -r <roadmap> -e TASK
```

## Exemplos de Uso

### Exemplo 1: Iniciar um Novo Sprint

```
Usuário: Quero iniciar um sprint para implementar a API de autenticação

Claude:
1. Verifica roadmaps disponíveis
   rmp road ls

2. Cria sprint
   rmp sprint new -r api-project -d "Sprint 1 - API Auth"

3. Cria tarefas estruturadas
   rmp task new -r api-project -d "Setup JWT library" -a "Add jwt-go dependency and configure" -e "Library imported and configured" -p 9 --severity 5
   rmp task new -r api-project -d "Create auth middleware" -a "Implement JWT verification middleware" -e "Middleware validates tokens correctly" -p 9 --severity 8
   rmp task new -r api-project -d "Add login endpoint" -a "Create POST /auth/login endpoint" -e "Returns valid JWT on correct credentials" -p 8 --severity 6

4. Adiciona tarefas ao sprint
   rmp sprint add -r api-project 1 1,2,3

5. Inicia sprint
   rmp sprint start -r api-project 1

6. Reporta status
   "Sprint 1 - API Auth iniciado com 3 tarefas. Prioridade média: 8.7"
```

### Exemplo 2: Progresso Durante Sprint

```
Usuário: Qual o progresso do sprint atual?

Claude:
1. Obtém sprint ativo
   rmp sprint ls -r api-project -s OPEN

2. Obtém estatísticas
   rmp sprint stats -r api-project 1

3. Lista tarefas do sprint
   rmp sprint tasks -r api-project 1

4. Reporta:
   "Sprint 1 - API Auth: 66% completo
    - COMPLETED: 2 tarefas (Setup JWT, Auth middleware)
    - DOING: 1 tarefa (Login endpoint)
    - Próxima entrega estimada: em breve"
```

### Exemplo 3: Completar Tarefa

```
Usuário: Terminei a implementação do middleware

Claude:
1. Verifica estado da tarefa
   rmp task get -r api-project 2

2. Transiciona para TESTING
   rmp task stat -r api-project 2 TESTING

3. [Simula ou aguarda testes]

4. Transiciona para COMPLETED
   rmp task stat -r api-project 2 COMPLETED

5. Atualiza prioridade da próxima tareha se necessário

6. Reporta:
   "Tarefa 2 (Create auth middleware) completada.
    Sprint 1 agora com 66% de conclusão."
```

## Códigos de Saída

| Código | Significado | Ação do Claude |
|--------|-------------|----------------|
| 0 | Sucesso | Continuar fluxo |
| 1 | Erro geral | Reportar erro e tentar alternativa |
| 2 | Uso inválido | Verificar sintaxe do comando |
| 3 | Sem roadmap | Solicitar seleção de roadmap |
| 4 | Não encontrado | Verificar IDs e existência |
| 5 | Já existe | Sugerir nome alternativo ou usar existente |
| 6 | Dados inválidos | Validar inputs antes de reenviar |
| 127 | Comando desconhecido | Verificar instalação do rmp |

## Formato de Resposta JSON

Todas as respostas de sucesso são JSON. O Claude deve parsear e apresentar de forma legível.

**Sucesso:**
```json
{
  "id": 42,
  "priority": 9,
  "severity": 5,
  "status": "DOING",
  "description": "...",
  "action": "...",
  "expected_result": "...",
  "created_at": "2026-03-12T14:30:00.000Z",
  "completed_at": null
}
```

**Erro (stderr):**
```
Error: Task with ID 999 not found in roadmap 'project1'
```

## Melhores Práticas

1. **Sempre verificar existência** antes de operar sobre entidades
2. **Usar operações em lote** quando possível para eficiência
3. **Manter audit trail** - todas as operações são logadas automaticamente
4. **Priorizar por urgency/impact** - usar ordenação do sprint
5. **Validar transições** - verificar se estado atual permite a transição
6. **Usar Unix conventions** - `ls`, `rm`, `new`, `stat`, `prio`, `sev`
7. **Formatar datas em ISO 8601** quando necessário
8. **Lidar com erros gracefully** - parsear stderr para mensagens claras

## Troubleshooting

### "rmp: command not found"
```bash
# Verificar instalação
which rmp

# Se não encontrado, reinstalar
zig build install

# Ou adicionar ao PATH
export PATH=$PATH:/path/to/LRoadmap/zig-out/bin
```

### "Roadmap not found"
```bash
# Listar roadmaps disponíveis
rmp road ls

# Criar se necessário
rmp road new <nome>
```

### "Task not found"
```bash
# Verificar IDs existentes
rmp task ls -r <roadmap>
```

### Erro de permissão em ~/.roadmaps
```bash
# Verificar permissões
ls -la ~/.roadmaps

# Corrigir se necessário
chmod 755 ~/.roadmaps
chmod 644 ~/.roadmaps/*.db
```

## Referências

- [SPEC/COMMANDS.md](SPEC/COMMANDS.md) - Referência completa de comandos
- [SPEC/DATA_FORMATS.md](SPEC/DATA_FORMATS.md) - Formatos de dados JSON
- [SPEC/DATABASE.md](SPEC/DATABASE.md) - Schema SQLite e queries
- [README.md](README.md) - Documentação geral do projeto
