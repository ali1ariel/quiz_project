defmodule QuizProjectWeb.Api.OpenApiController do
  use QuizProjectWeb, :controller

  @moduledoc """
  Serve o schema OpenAPI 3.1 da API v1 em `/api/openapi.json`.

  O schema é público e pronto para importar em clientes como as Actions de
  GPTs personalizados do ChatGPT (Importar de URL + autenticação Bearer).
  Os endpoints de emissão e revogação de token ficam de fora de propósito:
  agentes devem receber um token criado na tela de Configurações, nunca
  credenciais de login.
  """

  def show(conn, _params) do
    json(conn, spec(unverified_url(conn, "/api/v1")))
  end

  defp spec(base_url) do
    %{
      openapi: "3.1.0",
      info: %{
        title: "API de quizzes",
        version: "1.0.0",
        description:
          "Crie, edite, valide e publique quizzes. Todas as operações exigem um " <>
            "Bearer token gerado em Configurações → Tokens e retornam apenas os " <>
            "recursos da conta autenticada. Documentação completa em /api/docs."
      },
      servers: [%{url: base_url}],
      security: [%{bearerAuth: []}],
      paths: paths(),
      components: %{
        securitySchemes: %{
          bearerAuth: %{type: "http", scheme: "bearer", description: "Token quiz_..."}
        },
        schemas: schemas()
      }
    }
  end

  defp paths do
    %{
      "/quizzes" => %{
        get: %{
          operationId: "listQuizzes",
          summary: "Lista os quizzes da conta",
          description: "Do mais recente para o mais antigo, com resumo das versões.",
          responses: %{
            "200" => data_response("Lista de quizzes", array_of("Quiz")),
            "401" => error_response("Token ausente ou inválido")
          }
        },
        post: %{
          operationId: "createQuiz",
          summary: "Cria um quiz em rascunho",
          description:
            "Cria o quiz e sua versão 1 com status draft. O corpo pode ser vazio; " <>
              "nome e questões só são exigidos na publicação. Requer o escopo quizzes:write.",
          requestBody: json_body("QuizInput", required: false),
          responses: %{
            "201" => data_response("Versão criada", ref("Version")),
            "422" => error_response("Parâmetros inválidos")
          }
        }
      },
      "/quizzes/import" => %{
        post: %{
          operationId: "importQuiz",
          summary: "Importa um quiz completo em uma chamada",
          description:
            "Usa o formato de importação com chaves em português. " <>
              "Requer o escopo quizzes:write.",
          requestBody: json_body("ImportQuizInput", required: true),
          responses: %{
            "201" => data_response("Versão importada", ref("Version")),
            "422" => error_response("Documento inválido")
          }
        }
      },
      "/quizzes/{id}" => %{
        get: %{
          operationId: "getQuiz",
          summary: "Busca um quiz pelo ID",
          parameters: [id_param("ID do quiz (não da versão)")],
          responses: %{
            "200" => data_response("Quiz encontrado", ref("Quiz")),
            "404" => error_response("Inexistente ou de outra conta")
          }
        },
        patch: %{
          operationId: "setQuizActive",
          summary: "Ativa ou desativa um quiz",
          description: "active=false impede novas respostas; true reabre. Requer quizzes:write.",
          parameters: [id_param("ID do quiz")],
          requestBody: json_body("ActiveInput", required: true),
          responses: %{
            "200" => data_response("Quiz atualizado", ref("Quiz")),
            "404" => error_response("Inexistente ou de outra conta"),
            "422" => error_response("active precisa ser true ou false")
          }
        }
      },
      "/quizzes/{id}/drafts" => %{
        post: %{
          operationId: "createQuizDraft",
          summary: "Garante um rascunho editável",
          description:
            "Retorna o rascunho existente ou copia a última versão publicada para a " <>
              "próxima version_number. Não recebe body. Requer quizzes:write.",
          parameters: [id_param("ID do quiz")],
          responses: %{
            "201" => data_response("Rascunho disponível", ref("Version")),
            "404" => error_response("Inexistente ou de outra conta"),
            "409" => error_response("Sem versão publicada para copiar")
          }
        }
      },
      "/quiz-versions/{id}" => %{
        get: %{
          operationId: "getQuizVersion",
          summary: "Busca uma versão completa",
          description: "Inclui todas as questões e alternativas.",
          parameters: [id_param("ID da versão, obtido em Quiz.versions")],
          responses: %{
            "200" => data_response("Versão encontrada", ref("Version")),
            "404" => error_response("Inexistente ou de outra conta")
          }
        },
        patch: %{
          operationId: "updateQuizVersion",
          summary: "Atualiza metadados de um rascunho",
          description: "Corpo parcial; edita somente versões draft. Requer quizzes:write.",
          parameters: [id_param("ID da versão em rascunho")],
          requestBody: json_body("QuizInput", required: true),
          responses: %{
            "200" => data_response("Versão atualizada", ref("Version")),
            "404" => error_response("Inexistente ou de outra conta"),
            "422" => error_response("Versão publicada ou parâmetros inválidos")
          }
        }
      },
      "/quiz-versions/{id}/validate" => %{
        post: %{
          operationId: "validateQuizVersion",
          summary: "Valida um rascunho sem alterar nada",
          description:
            "Executa as regras da publicação. Uma validação negativa ainda retorna " <>
              "HTTP 200; consulte data.valid e data.errors. Não recebe body.",
          parameters: [id_param("ID da versão")],
          responses: %{
            "200" => data_response("Resultado da validação", ref("ValidationResult")),
            "404" => error_response("Inexistente ou de outra conta")
          }
        }
      },
      "/quiz-versions/{id}/publish" => %{
        post: %{
          operationId: "publishQuizVersion",
          summary: "Publica um rascunho validado",
          description:
            "Valida, publica e congela a versão. Não recebe body. Requer quizzes:publish.",
          parameters: [id_param("ID da versão em rascunho")],
          responses: %{
            "200" => data_response("Versão publicada", ref("Version")),
            "404" => error_response("Inexistente ou de outra conta"),
            "422" => error_response("Conteúdo inválido; erros em error.details")
          }
        }
      },
      "/quiz-versions/{id}/questions" => %{
        post: %{
          operationId: "createQuestion",
          summary: "Cria uma questão no rascunho",
          description:
            "Adiciona ao fim; a posição é automática. Permite salvar incompleto — " <>
              "use a validação antes de publicar. Requer quizzes:write.",
          parameters: [id_param("ID da versão em rascunho")],
          requestBody: json_body("QuestionInput", required: true),
          responses: %{
            "201" => data_response("Questão criada", ref("Question")),
            "404" => error_response("Inexistente ou de outra conta"),
            "422" => error_response("Versão publicada ou parâmetros inválidos")
          }
        }
      },
      "/questions/{id}" => %{
        patch: %{
          operationId: "updateQuestion",
          summary: "Atualiza uma questão de rascunho",
          description:
            "Se options for enviado, substitui a coleção inteira: itens sem id são " <>
              "criados e alternativas omitidas são excluídas. Se options for omitido, " <>
              "as alternativas atuais permanecem. Requer quizzes:write.",
          parameters: [id_param("ID da questão (não o identity_key)")],
          requestBody: json_body("QuestionInput", required: true),
          responses: %{
            "200" => data_response("Questão atualizada", ref("Question")),
            "404" => error_response("Inexistente ou de outra conta"),
            "422" => error_response("Versão publicada ou parâmetros inválidos")
          }
        },
        delete: %{
          operationId: "deleteQuestion",
          summary: "Remove uma questão do rascunho",
          description: "Renumera as posições restantes. Requer quizzes:write.",
          parameters: [id_param("ID da questão")],
          responses: %{
            "204" => %{description: "Removida; sem corpo"},
            "404" => error_response("Inexistente ou de outra conta"),
            "409" => error_response("Versão não editável")
          }
        }
      }
    }
  end

  defp schemas do
    %{
      "Quiz" => %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid"},
          public_slug: %{type: "string", description: "Slug do link público em /q/:public_slug"},
          active: %{type: "boolean"},
          inserted_at: %{type: "string", format: "date-time"},
          updated_at: %{type: "string", format: "date-time"},
          versions: array_of("VersionSummary").schema
        }
      },
      "VersionSummary" => %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid"},
          version_number: %{type: "integer"},
          name: %{type: "string"},
          status: %{type: "string", enum: ["draft", "published"]},
          published_at: %{type: ["string", "null"], format: "date-time"},
          updated_at: %{type: "string", format: "date-time"}
        }
      },
      "Version" => %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid"},
          quiz_id: %{type: "string", format: "uuid"},
          version_number: %{type: "integer"},
          name: %{type: "string"},
          description: %{type: "string"},
          total_points: %{type: "string", description: "Decimal como string, ex.: \"100\""},
          unequal_weights: %{type: "boolean"},
          question_order_mode: %{type: "string", enum: ["fixed", "random", "ai"]},
          status: %{type: "string", enum: ["draft", "published"]},
          published_at: %{type: ["string", "null"], format: "date-time"},
          changelog: %{type: "array", items: %{type: "string"}},
          inserted_at: %{type: "string", format: "date-time"},
          updated_at: %{type: "string", format: "date-time"},
          questions: array_of("Question").schema
        }
      },
      "Question" => %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid"},
          identity_key: %{type: "string", format: "uuid"},
          position: %{type: "integer", description: "Iniciada em zero"},
          statement: %{type: "string"},
          type: %{type: "string", enum: ["true_false", "single", "multiple", "text"]},
          allow_partial_credit: %{type: "boolean"},
          true_false_answer: %{type: ["boolean", "null"]},
          editor_note: %{type: ["string", "null"]},
          weight: %{type: ["string", "null"], description: "Decimal como string"},
          annulled: %{type: "boolean"},
          annulled_reason: %{type: ["string", "null"]},
          options: array_of("Option").schema
        }
      },
      "Option" => %{
        type: "object",
        properties: %{
          id: %{type: "string", format: "uuid"},
          identity_key: %{type: "string", format: "uuid"},
          position: %{type: "integer"},
          text: %{type: "string"},
          correct: %{type: "boolean"}
        }
      },
      "QuizInput" => %{
        type: "object",
        description: "Todos os campos são opcionais; envie apenas o que deseja alterar.",
        properties: %{
          name: %{type: "string"},
          description: %{type: "string"},
          total_points: %{type: "number", exclusiveMinimum: 0},
          unequal_weights: %{type: "boolean"},
          question_order_mode: %{type: "string", enum: ["fixed", "random", "ai"]}
        }
      },
      "ActiveInput" => %{
        type: "object",
        required: ["active"],
        properties: %{active: %{type: "boolean"}}
      },
      "QuestionInput" => %{
        type: "object",
        properties: %{
          statement: %{type: "string"},
          type: %{type: "string", enum: ["true_false", "single", "multiple", "text"]},
          allow_partial_credit: %{type: "boolean", description: "Use apenas com multiple"},
          true_false_answer: %{
            type: ["boolean", "null"],
            description: "Exigido para publicar questões true_false"
          },
          editor_note: %{type: ["string", "null"]},
          weight: %{type: ["number", "null"]},
          position: %{type: "integer"},
          options: %{type: "array", items: ref("OptionInput")}
        }
      },
      "OptionInput" => %{
        type: "object",
        properties: %{
          id: %{
            type: "string",
            format: "uuid",
            description: "Presente preserva a alternativa; ausente cria uma nova"
          },
          text: %{type: "string"},
          correct: %{type: "boolean", default: false},
          position: %{type: "integer", default: 0}
        }
      },
      "ImportQuizInput" => %{
        type: "object",
        description: "Formato de importação com chaves em português.",
        required: ["nome", "questoes"],
        properties: %{
          nome: %{type: "string", minLength: 1},
          descricao: %{type: "string"},
          nota_total: %{type: "number", exclusiveMinimum: 0, default: 100},
          pesos_desiguais: %{type: "boolean", default: false},
          modo_ordem: %{type: "string", enum: ["fixa", "aleatoria", "ia"], default: "fixa"},
          questoes: %{type: "array", minItems: 1, items: ref("ImportQuestionInput")}
        }
      },
      "ImportQuestionInput" => %{
        type: "object",
        required: ["enunciado", "tipo"],
        properties: %{
          enunciado: %{type: "string", minLength: 1},
          tipo: %{
            type: "string",
            enum: ["verdadeiro_falso", "unica", "multipla", "discursiva"]
          },
          resposta_verdadeiro_falso: %{
            type: "boolean",
            description: "Obrigatório em verdadeiro_falso"
          },
          alternativas: %{
            type: "array",
            minItems: 2,
            description: "Obrigatório em unica e multipla",
            items: ref("ImportOptionInput")
          },
          nota_parcial: %{type: "boolean", description: "Opcional em multipla"},
          resposta_referencia: %{
            type: "string",
            description: "Referência para correção discursiva por IA"
          },
          peso: %{type: "number", minimum: 0}
        }
      },
      "ImportOptionInput" => %{
        type: "object",
        required: ["texto"],
        properties: %{
          texto: %{type: "string"},
          correta: %{type: "boolean", default: false}
        }
      },
      "ValidationResult" => %{
        type: "object",
        properties: %{
          valid: %{type: "boolean"},
          errors: %{type: "array", items: %{type: "string"}}
        }
      },
      "Error" => %{
        type: "object",
        properties: %{
          error: %{
            type: "object",
            properties: %{
              code: %{type: "string"},
              message: %{type: "string"},
              details: %{type: "array", items: %{type: "string"}}
            }
          }
        }
      }
    }
  end

  defp ref(name), do: %{"$ref" => "#/components/schemas/#{name}"}

  defp array_of(name), do: %{schema: %{type: "array", items: ref(name)}}

  defp id_param(description) do
    %{
      name: "id",
      in: "path",
      required: true,
      description: description,
      schema: %{type: "string", format: "uuid"}
    }
  end

  defp json_body(schema_name, required: required) do
    %{
      required: required,
      content: %{"application/json" => %{schema: ref(schema_name)}}
    }
  end

  defp data_response(description, schema) do
    inner =
      case schema do
        %{schema: array_schema} -> array_schema
        other -> other
      end

    %{
      description: description,
      content: %{
        "application/json" => %{
          schema: %{type: "object", properties: %{data: inner}}
        }
      }
    }
  end

  defp error_response(description) do
    %{
      description: description,
      content: %{"application/json" => %{schema: ref("Error")}}
    }
  end
end
