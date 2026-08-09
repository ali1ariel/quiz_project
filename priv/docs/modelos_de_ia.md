# Atualização de modelos de IA

Modelo de IA envelhece rápido: preço muda, modelo novo sai, modelo velho é
desligado. Este documento diz **onde** os dados moram e **como** atualizá-los,
para a informação não apodrecer espalhada pelo código.

Referência da última conferência: **2026-08-09**.

## Onde estão os dados

São dois arquivos, e só dois.

| O quê | Arquivo | Detalhe |
| --- | --- | --- |
| Modelo padrão de cada provedor | `config/config.exs` | Três linhas: `openai_model`, `gemini_model`, `anthropic_model` |
| Preço, janela de contexto e faixa | `lib/quiz_project/ai.ex` | Atributo `@models` |
| Provedores oferecidos na escolha | `lib/quiz_project/ai.ex` | Atributo `@providers` |

O resto **lê** desses dois e não guarda cópia:

- `config/runtime.exs` só sobrescreve o modelo quando `OPENAI_MODEL`,
  `GEMINI_MODEL` ou `ANTHROPIC_MODEL` está no ambiente.
- `QuizProject.AI.Claude`, `.OpenAI` e `.Gemini` chamam
  `Application.get_env/2` sem valor padrão próprio.
- A confirmação de curadoria no leitor (`ContentsLive.Read`) monta a lista de
  escolha com `QuizProject.AI.catalog/0` e valida o que volta do formulário com
  `QuizProject.AI.resolve/2`.

Um teste em `test/quiz_project/ai_providers_test.exs` falha se um modelo padrão
sair da tabela — foi assim que `gemini-2.0-flash` passou meses apontando para um
modelo desligado sem ninguém notar.

Se você se pegar escrevendo o nome de um modelo num quarto lugar, o lugar está
errado.

## Fontes oficiais

Conferir na documentação do fabricante, não de memória:

| Provedor | Preços | Modelos |
| --- | --- | --- |
| Anthropic | <https://platform.claude.com/docs/en/about-claude/pricing> | <https://platform.claude.com/docs/en/about-claude/models/overview> |
| OpenAI | <https://developers.openai.com/api/docs/pricing> | <https://developers.openai.com/api/docs/models> |
| Google | <https://ai.google.dev/gemini-api/docs/pricing> | <https://ai.google.dev/gemini-api/docs/models> |

## Procedimento

1. Abrir as três páginas de preço e comparar com `@models`.
2. Corrigir preço de entrada e saída (dólares por **milhão** de tokens).
3. Se o modelo novo é a versão atual de uma faixa, ele **substitui** o que
   estava naquela faixa. Se ele abre uma faixa que o provedor não tinha, entra
   sem tirar ninguém.
4. Verificar se algum modelo padrão de `config/config.exs` saiu junto — o teste
   de catálogo falha se sair, mas é melhor perceber antes.
5. Se um modelo padrão de `config/config.exs` foi desligado, trocar pelo
   sucessor indicado pelo fabricante.
6. Atualizar a data de conferência no topo deste arquivo e no comentário de
   `@models`.
7. `mix precommit`.

## Escolha por requisição

A curadoria de capítulo de livro deixa quem clica escolher provedor e modelo na
hora, e essa escolha vale **só para aquela chamada**: o provider global continua
mandando em tags, correção, referência e progressão. O caminho é `opts` com
`:provider` e `:model`, de `Books.curate_chapter_async/3` até
`QuizProject.AI.curate_mindmap/2`; sem `opts`, tudo se comporta como antes.

Duas regras que não podem ser afrouxadas:

- **O que vem do formulário é texto, nunca átomo.** `@providers` mapeia um
  identificador em texto para o módulo. Converter nome de módulo vindo do
  navegador é transformar um `<select>` em execução de código arbitrário.
- **`resolve/2` é a autorização, o botão é só a interface.** Ele recusa provedor
  desconhecido, modelo desconhecido e modelo que não pertence ao provedor
  escolhido. O botão desabilitado ajuda quem usa; o evento chega pelo socket e
  não se confia nele.

## Regras da tabela

- **O critério de entrada é cobertura de faixa, não histórico de versão.** Para
  cada provedor, a versão atual de cada faixa que ele oferece — uma por faixa,
  e o teste de catálogo falha se houver duas. É o que a tela de escolha precisa:
  poder subir quando o capítulo é difícil e descer quando é simples, sem trocar
  de provedor.

  Isto substitui um critério anterior ("a atual e a anterior de cada linha"), que
  era mais fácil de aplicar e pior de usar: ele apagou o único Pro do Gemini e
  deixou o provedor sem nenhuma opção capaz. Versão antiga não fica só por ser
  conhecida — quem tiver uma fixada por variável de ambiente continua sendo
  atendido, ela só aparece como "sem preço tabelado".
- **`context: nil` quando a fonte não publica o número.** A interface mostra
  desconhecido como desconhecido. Preencher de memória transforma palpite em
  fato na tela do usuário.
- **Preço com faixas fica na faixa que se aplica ao nosso uso.** Gemini Pro, por
  exemplo, cobra mais acima de 200k tokens de prompt, e capítulo de livro não
  chega lá — entraria pela faixa baixa, com comentário dizendo por quê. Nenhum
  modelo da tabela atual cobra assim; a regra vale para quando um entrar.
- **Promoção não entra.** Sonnet 5 teve preço promocional até 2026-08-31; a
  tabela guarda o preço cheio, para a estimativa não encolher sozinha na virada
  do mês. Estimativa que erra para cima não surpreende ninguém na fatura.
- **A janela é em tokens, e token não é caractere.** Opus 5, Opus 4.8/4.7/4.6,
  Sonnet 5 e Sonnet 4.6 têm todos 1M — a divisão não é Opus contra Sonnet, é por
  geração (Sonnet 4.5 e Opus 4.5 têm 200k). Mas o tokenizador introduzido no
  Opus 4.7 produz ~30% mais tokens para o mesmo texto: 1M de tokens cabe ~555k
  palavras no Opus 5 e ~750k no Opus 4.6. Nossa estimativa usa uma razão fixa de
  caracteres por token, então ela **subestima** nos modelos de 4.7 em diante.
  Calibrar por modelo é o que `priv/docs/calibrar_tokens.exs` mede.
- **Preço não varia entre versões da mesma família.** Todo Opus é $5/$25, todo
  Sonnet é $3/$15. Se uma versão nova parecer ter preço diferente, conferir duas
  vezes antes de escrever — é mais provável ser leitura errada da página.
- **Modelo fora da tabela não quebra nada.** `pricing` e `context` viram `nil`,
  e a tela diz "modelo sem preço tabelado".
- **`tier` é julgamento nosso, não número de fabricante.** São quatro:
  `:frontier` (topo premium — Fable 5, GPT-5.5 Pro), `:flagship` (o cavalo de
  batalha capaz), `:balanced` e `:light`. `frontier` existe separado de `flagship`
  porque o preço entre os dois varia de 2x a 6x, e juntá-los esconderia
  justamente o que a tela existe para mostrar. Modelo novo entra na faixa que
  corresponde à posição dele na linha do fabricante.

  Só `:light` dispara aviso na interface. É a faixa econômica (mini, nano, lite, flash-lite,
  haiku): a decomposição exige devolver o capítulo inteiro em JSON estruturado, e
  esses modelos costumam truncar ou quebrar o formato — falhar depois de gastar é
  o pior dos resultados.

## O que não dá para fazer

**Saldo e créditos da conta não são expostos pela API de inferência** — de
nenhum dos três provedores. Não há endpoint para consultar. O que existe, na
Anthropic, é o relatório de uso e custo da Admin API, que exige uma chave de
administrador (`sk-ant-admin…`) diferente da chave de inferência e é uma
integração à parte. Por isso a confirmação de curadoria mostra "saldo:
indisponível" e explica o motivo, em vez de deixar um campo vazio parecendo
falha de integração.

## Custo estimado da curadoria

A conta tem duas partes, e as duas são aproximação:

1. **Entrada** — `Books.estimate_tokens/1`, razão fixa de caracteres por token.
2. **Saída** — `@curation_output_ratio` em `books.ex`, hoje **2,5x a entrada**.

O `2,5` não é intuição: veio de comparar a estimativa com uma fatura real. Um
capítulo de 81.332 caracteres curado com `claude-opus-5` custou **US$ 1,47**,
enquanto a versão anterior da conta (saída = entrada) previa US$ 0,65 — errava
por 2,3x. O que faltava:

- a estrutura JSON em cima do texto devolvido (ids de nó, hierarquia,
  referências cruzadas);
- **o raciocínio, que é cobrado como saída** — a curadoria roda com
  `effort: "high"` e, no Opus 5, raciocínio vem ligado por padrão;
- a razão de caracteres por token, que subestima nos modelos de 4.7 em diante.

Como o `2,5` absorve também esse terceiro item, **ele precisa ser refeito se
`@chars_per_token` mudar** — os dois números estão acoplados de propósito, para
não empilhar margem sobre margem, e isso está dito onde eles moram.

**O `2,5` é só o ponto de partida.** Desde que o uso real passou a ser gravado,
ele vale apenas enquanto não há nenhuma curadoria feita. A partir da primeira,
`Books.measured_output_ratio/0` calcula a razão agregada das curadorias reais e a
previsão passa a sair dela — e o modal diz qual das duas está valendo
("estimado" contra "média de N curadorias").

O uso vem do próprio provedor (`usage.output_tokens` na Anthropic,
`completion_tokens` na OpenAI, `candidatesTokenCount` no Gemini) e fica em
`chapters.usage_input_tokens` / `usage_output_tokens` / `curated_model`. Falha de
curadoria e provedor local gravam **nulo**, não zero: zero entraria na média
afirmando uma medição que não houve.

A razão é medida contra a *estimativa* de entrada, não contra a entrada real —
de propósito. A previsão parte da estimativa, então é o erro dela ponta a ponta
que precisa ser corrigido; medir só o lado da saída deixaria o erro do
tokenizador de fora.

## Contagem de tokens

A estimativa em `QuizProject.AdaptiveStudy.Books.estimate_tokens/1` é
aproximação de tokenizador, não medição. Para calibrar contra a contagem real
da Anthropic (endpoint exato e gratuito):

```sh
ANTHROPIC_API_KEY=sk-... mix run priv/docs/calibrar_tokens.exs
```

O script imprime o desvio por capítulo e agregado, e diz como ajustar os pesos.
