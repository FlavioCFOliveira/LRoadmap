# Plano de Implementação: Conformidade com a SPEC do LRoadmap

## Contexto
Este plano visa alinhar a CLI LRoadmap integralmente com a sua especificação técnica (SPEC). O objetivo é garantir um comportamento previsível e padronizado para integração com fluxos de trabalho agenticos, corrigindo formatos de output, completando aliases de comandos e aumentando a precisão temporal.

## Mudanças Propostas

### 1. Refatoração do Sistema de Output (Prioridade Crítica)
- **JSON Direto para Queries e Criação**:
  - Modificar `src/utils/json.zig` para remover o wrapper `{"status": "success", "data": ...}`.
  - Comandos de consulta (`list`, `get`, `stats`, `history`) devem retornar o objeto ou array JSON diretamente no `stdout`.
  - Comandos de criação devem retornar apenas o objeto de identificação (ex: `{"id": 42}`).
- **Silenciamento de Comandos de Modificação**:
  - Garantir que comandos que alteram o estado (status, prioridade, remoção, início/fim de sprint) não produzam qualquer output no `stdout` em caso de sucesso.
- **Erros em Texto Simples no Stderr**:
  - Refatorar `printError` e `printErrorWithHelp` em `src/cli.zig` para emitir mensagens em texto simples para o `stderr`.
  - Erros de input devem ser seguidos pelo texto de ajuda específico do comando.

### 2. Implementação de Aliases de Comando (Faltantes)
- Implementar e validar os seguintes aliases conforme a SPEC:
  - `roadmap`: `road`, `ls`, `new`, `rm`.
  - `task`: `ls`, `new`, `stat`, `prio`, `sev`, `rm`.
  - `sprint`: `ls`, `new`, `upd`, `add` (para add-tasks), `rm-tasks`, `mv-tasks`.
  - `audit`: `aud`, `ls`, `hist`.

### 3. Precisão de Milissegundos em Timestamps
- Atualizar `src/utils/time.zig` para capturar milissegundos reais usando `std.time.milliTimestamp()`.
- Ajustar `ISO8601_FORMAT` para incluir a fração de segundos com 3 dígitos (`.sss`).
- Garantir que todos os logs de auditoria e campos de data (`created_at`, `completed_at`, etc.) utilizem esta nova precisão.

### 4. Validação de Operações Bulk
- Verificar se todos os comandos que aceitam IDs múltiplos (ex: `1,2,3`) estão a processar a lista corretamente e sem produzir output desnecessário para cada item.

## Ficheiros Críticos
- `src/cli.zig`: Ponto central de controlo de output e despacho de comandos.
- `src/utils/json.zig`: Camada de serialização e resposta.
- `src/utils/time.zig`: Utilitário de formatação temporal.
- `src/commands/*.zig`: Lógica individual de cada módulo (task, roadmap, sprint, audit).

## Plano de Validação
- **Testes Unitários**: `zig build test` (adicionar testes para precisão de tempo e formato JSON).
- **Verificação CLI**:
  - Executar `rmp task ls -r project1` e validar output `[...]`.
  - Executar `rmp task stat -r project1 1 COMPLETED` e validar ausência de output.
  - Executar comando inválido e validar erro em texto no `stderr`.
  - Verificar se `rmp roadmap use` persiste corretamente e permite comandos subsequentes sem `-r`.
