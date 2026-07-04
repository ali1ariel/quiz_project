# Formato de importação de quiz (para gerar com IA)

Gere **um único objeto JSON** seguindo exatamente o formato abaixo, com as
chaves em português. Devolva apenas o JSON — sem texto antes ou depois e sem
cercas de código (nada de ```). Chaves desconhecidas são ignoradas; JSON não
aceita comentários.

## Objeto raiz

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `nome` | texto | sim | Título do quiz (não pode ser vazio) |
| `descricao` | texto | não | Descrição exibida ao participante (padrão: vazio) |
| `nota_total` | número > 0 | não | Nota máxima do quiz (padrão: 100) |
| `pesos_desiguais` | booleano | não | Se `true`, cada questão pode ter `peso` próprio (padrão: `false`) |
| `modo_ordem` | texto | não | `"fixa"`, `"aleatoria"` ou `"ia"` (padrão: `"fixa"`) |
| `questoes` | lista | sim | Ao menos uma questão |

## Cada item de `questoes`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `enunciado` | texto | sim | O texto da pergunta |
| `tipo` | texto | sim | `"verdadeiro_falso"`, `"unica"`, `"multipla"` ou `"discursiva"` |
| `resposta_verdadeiro_falso` | booleano | só em `verdadeiro_falso` | `true` ou `false` |
| `alternativas` | lista | só em `unica` e `multipla` | Ver tabela abaixo |
| `nota_parcial` | booleano | não (só `multipla`) | `true` dá nota proporcional às corretas |
| `resposta_referencia` | texto | não (recomendado em `discursiva`) | Resposta esperada; aparece no resultado e serve de gabarito para a correção por IA |
| `peso` | número ≥ 0 | não | Só é usado quando `pesos_desiguais` é `true` |

## Cada item de `alternativas`

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `texto` | texto | sim | O texto da alternativa |
| `correta` | booleano | não | `true` marca a alternativa como correta (padrão: `false`) |

## Regras por tipo de questão

- **`verdadeiro_falso`** — defina `resposta_verdadeiro_falso`. Não tem alternativas.
- **`unica`** — pelo menos 2 alternativas; **exatamente 1** com `"correta": true`.
- **`multipla`** — pelo menos 2 alternativas; **1 ou mais** com `"correta": true`. Com `"nota_parcial": true`, acertar só parte das corretas (sem marcar nenhuma errada) vale proporcional; marcar qualquer errada zera a questão.
- **`discursiva`** — sem alternativas. É corrigida por IA comparando a resposta do participante com `resposta_referencia`.

## Exemplo completo e válido

```json
{
  "nome": "Título do quiz",
  "descricao": "Descrição opcional exibida ao participante",
  "nota_total": 100,
  "pesos_desiguais": false,
  "modo_ordem": "fixa",
  "questoes": [
    {
      "enunciado": "Pergunta de verdadeiro ou falso?",
      "tipo": "verdadeiro_falso",
      "resposta_verdadeiro_falso": true,
      "resposta_referencia": "Opcional: explica a resposta esperada."
    },
    {
      "enunciado": "Pergunta com uma única alternativa correta?",
      "tipo": "unica",
      "alternativas": [
        { "texto": "Alternativa correta", "correta": true },
        { "texto": "Alternativa incorreta", "correta": false },
        { "texto": "Outra alternativa", "correta": false }
      ]
    },
    {
      "enunciado": "Pergunta com múltiplas alternativas corretas?",
      "tipo": "multipla",
      "nota_parcial": true,
      "alternativas": [
        { "texto": "Correta 1", "correta": true },
        { "texto": "Correta 2", "correta": true },
        { "texto": "Incorreta", "correta": false }
      ]
    },
    {
      "enunciado": "Pergunta discursiva de resposta aberta?",
      "tipo": "discursiva",
      "resposta_referencia": "Resposta de referência usada pela IA para corrigir."
    }
  ]
}
```
