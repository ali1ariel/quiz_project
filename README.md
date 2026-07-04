# Quiz Project

Protótipo funcional de um serviço de quizzes com Phoenix LiveView + Ash Framework +
PostgreSQL e correção de questões discursivas por IA (OpenAI/Gemini).

## Como rodar

```bash
mix setup          # dependências, banco e assets
mix phx.server     # http://localhost:4000
mix test           # suíte completa
```

Requisitos: Elixir 1.18+, PostgreSQL 16+ (usuário/senha `postgres` em dev).

## O que o protótipo faz

- **Contas**: cadastro/login obrigatórios para criar quizzes; responder é aberto.
  Participantes anônimos usam um token de sessão; se logarem no meio da resposta,
  as tentativas anônimas são associadas à conta.
- **Criação**: nome, descrição, nota total (padrão 100), toggle de pesos desiguais,
  modo de ordem das questões (definida, aleatória, aleatória por IA). Rascunho com
  autosave contínuo; publicação valida e congela a versão.
- **Tipos de questão**: verdadeiro/falso, uma correta, múltiplas corretas (com nota
  parcial opcional) e discursiva. Cada questão tem nota do editor (opcional) e peso
  (ativo só com pesos desiguais; sem peso, a nota restante é distribuída).
- **Importação JSON**: quiz completo entra como rascunho para revisão (formato abaixo).
- **Versionamento**: alterações estruturais geram nova versão; a anterior fica
  intacta e as tentativas antigas apontam para a versão respondida. Histórico com
  changelog simples ("Questão 3 removida", "Peso da questão 2 alterado"...).
- **Reaproveitamento**: nova tentativa em versão mais recente importa automaticamente
  respostas de questões compatíveis (identidade estável + hash dos campos que afetam
  a resposta), com pill "Importada da versão anterior"; editar remove a pill.
- **Anulação**: questão de versão publicada pode ser anulada com motivo; ela continua
  visível no resultado com selo e todos recebem a pontuação integral, para sempre.
- **Resposta**: 10 questões por página; paginação com status (vermelho = sem resposta,
  amarelo = marcadas para depois, verde = completa; vermelho tem prioridade); botões
  "Marcar para responder depois", "Não sei a resposta" (só sem resposta preenchida),
  "Limpar respostas" e "Restaurar" com janela de 10 segundos. Estado salvo a cada
  interação. Confirmação com pendências converte tudo em "não sei" após modal.
- **Correção**: só após finalizar. Objetivas mostram resposta, gabarito e nota.
  Discursivas são avaliadas por IA contra a referência do criador (resposta de
  referência ou nota do editor); sem referência, a IA gera a própria e isso fica
  sinalizado. A nota é a porcentagem × peso da questão.
- **Privacidade**: o criador vê as respostas de cada tentativa na mesma tela do
  participante (somente leitura), mas apenas com a identificação escolhida no campo
  "Como prefere se identificar?" — nunca nome real, e-mail ou dados da conta.

## Integração com IA

Configurada por variáveis de ambiente do sistema (não por usuário):

| Variável | Uso |
| --- | --- |
| `AI_PROVIDER` | `openai`, `gemini` ou `fake` (explícito; opcional) |
| `OPENAI_API_KEY` / `OPENAI_MODEL` | OpenAI (padrão `gpt-4o-mini`) |
| `GEMINI_API_KEY` / `GEMINI_MODEL` | Gemini (padrão `gemini-2.0-flash`) |

Sem chave nenhuma, o provider `Fake` (heurística local determinística) é usado —
útil em dev/teste. Operações: gerar até 4 tags internas por questão na publicação
(usadas pela ordenação por IA, sem chamadas em tempo de resposta), corrigir resposta
discursiva e gerar referência quando o criador não forneceu.

## Formato do JSON de importação

```json
{
  "nome": "Meu quiz",
  "descricao": "Opcional",
  "nota_total": 100,
  "pesos_desiguais": false,
  "modo_ordem": "fixa | aleatoria | ia",
  "questoes": [
    {
      "enunciado": "Texto da pergunta",
      "tipo": "verdadeiro_falso | unica | multipla | discursiva",
      "resposta_verdadeiro_falso": true,
      "alternativas": [{ "texto": "...", "correta": true }],
      "nota_parcial": true,
      "resposta_referencia": "Só para discursivas",
      "nota_editor": "Opcional",
      "peso": 10
    }
  ]
}
```

## Arquitetura

Três domínios Ash (`lib/quiz_project/`):

- **Accounts** — `User` (bcrypt, e-mail citext único).
- **Quizzes** — `Quiz` (agrupador + slug público), `QuizVersion` (rascunho/publicada,
  changelog), `Question` (identidade estável entre versões, hash de compatibilidade,
  anulação, tags de IA), `Option` (identidade estável). Módulos de apoio: `Publisher`
  (validação/congelamento), `Changelog`, `Compatibility`, `Scoring`, `TagOrdering`,
  `Importer`.
- **Attempts** — `Attempt` (ordem fixa congelada, identificação escolhida, token ou
  conta), `Answer` (payload por tipo, estados, backup de limpeza, campos de correção),
  `Grader`.

A camada de IA (`QuizProject.AI`) expõe uma fachada com providers plugáveis
(`OpenAI`, `Gemini`, `Fake`) atrás de um behaviour — a regra de negócio nunca fala
com um provider direto.

As funções públicas dos módulos de domínio são a porta de entrada da camada web e
fazem as checagens de autorização (dono do quiz, participante da tentativa)
explicitamente; as ações Ash internas rodam com `authorize?: false`.

Regras de compatibilidade entre versões: quebram — enunciado, tipo, alternativas
(texto/corretas/identidade), regra de nota parcial, resposta de referência, nota do
editor em discursivas, anulação, remoção. Não quebram — peso, nota total, descrição,
ordem, tags de IA e metadados.
