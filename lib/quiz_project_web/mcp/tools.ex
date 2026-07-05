defmodule QuizProjectWeb.Mcp.Tools do
  @moduledoc "Ferramentas MCP que espelham os endpoints JSON de /api/v1."

  alias QuizProject.Quizzes
  alias QuizProjectWeb.Api.{Params, Serializer}

  @write_scope "quizzes:write"
  @publish_scope "quizzes:publish"

  @option_schema %{
    type: "object",
    properties: %{
      "id" => %{type: "string", description: "ID da alternativa existente (para atualização)"},
      "text" => %{type: "string", description: "Texto da alternativa"},
      "correct" => %{type: "boolean", description: "Se a alternativa é correta"},
      "position" => %{type: "integer", description: "Posição da alternativa"}
    },
    required: ["text"]
  }

  @quiz_properties %{
    "name" => %{type: "string", description: "Nome do quiz"},
    "description" => %{type: "string", description: "Descrição do quiz"},
    "total_points" => %{type: "number", description: "Pontuação total do quiz"},
    "unequal_weights" => %{type: "boolean", description: "Permite pesos diferentes por questão"},
    "question_order_mode" => %{
      type: "string",
      enum: ["fixed", "random", "ai"],
      description: "Modo de ordenação das questões"
    }
  }

  @question_properties %{
    "statement" => %{type: "string", description: "Enunciado da questão"},
    "type" => %{
      type: "string",
      enum: ["true_false", "single", "multiple", "text"],
      description: "Tipo da questão"
    },
    "allow_partial_credit" => %{
      type: "boolean",
      description: "Permite crédito parcial (tipo multiple)"
    },
    "true_false_answer" => %{
      type: "boolean",
      description: "Resposta correta (tipo true_false)"
    },
    "editor_note" => %{type: "string", description: "Nota interna do editor"},
    "weight" => %{type: "number", description: "Peso da questão"},
    "position" => %{type: "integer", description: "Posição da questão"},
    "options" => %{
      type: "array",
      items: @option_schema,
      description: "Alternativas da questão (tipos single e multiple)"
    }
  }

  @tools %{
    "list_quizzes" => %{
      description: "Lista os quizzes do usuário autenticado com o resumo de suas versões.",
      scope: nil,
      properties: %{},
      required: []
    },
    "get_quiz" => %{
      description: "Busca um quiz do usuário pelo ID, incluindo o resumo de suas versões.",
      scope: nil,
      properties: %{"quiz_id" => %{type: "string", description: "ID do quiz"}},
      required: ["quiz_id"]
    },
    "create_quiz" => %{
      description: "Cria um quiz novo em rascunho e retorna a versão criada com suas questões.",
      scope: @write_scope,
      properties: @quiz_properties,
      required: []
    },
    "import_quiz" => %{
      description:
        "Importa um quiz completo a partir do formato JSON de importação " <>
          "(chaves em português: nome, descricao, questoes, enunciado, tipo etc.).",
      scope: @write_scope,
      properties: %{
        "data" => %{type: "object", description: "Documento JSON no formato de importação"}
      },
      required: ["data"]
    },
    "set_quiz_active" => %{
      description: "Ativa ou desativa um quiz publicado.",
      scope: @write_scope,
      properties: %{
        "quiz_id" => %{type: "string", description: "ID do quiz"},
        "active" => %{type: "boolean", description: "true para ativar, false para desativar"}
      },
      required: ["quiz_id", "active"]
    },
    "create_quiz_draft" => %{
      description: "Garante um rascunho editável para o quiz (cria a partir da última versão).",
      scope: @write_scope,
      properties: %{"quiz_id" => %{type: "string", description: "ID do quiz"}},
      required: ["quiz_id"]
    },
    "get_quiz_version" => %{
      description: "Busca uma versão de quiz pelo ID, incluindo questões e alternativas.",
      scope: nil,
      properties: %{"version_id" => %{type: "string", description: "ID da versão"}},
      required: ["version_id"]
    },
    "update_quiz_version" => %{
      description: "Atualiza os metadados de uma versão em rascunho.",
      scope: @write_scope,
      properties:
        Map.put(@quiz_properties, "version_id", %{
          type: "string",
          description: "ID da versão em rascunho"
        }),
      required: ["version_id"]
    },
    "validate_quiz_version" => %{
      description: "Valida uma versão em rascunho e retorna a lista de problemas encontrados.",
      scope: nil,
      properties: %{"version_id" => %{type: "string", description: "ID da versão"}},
      required: ["version_id"]
    },
    "publish_quiz_version" => %{
      description: "Publica uma versão em rascunho, tornando o quiz disponível ao público.",
      scope: @publish_scope,
      properties: %{"version_id" => %{type: "string", description: "ID da versão em rascunho"}},
      required: ["version_id"]
    },
    "create_question" => %{
      description: "Cria uma questão em uma versão em rascunho.",
      scope: @write_scope,
      properties:
        Map.put(@question_properties, "version_id", %{
          type: "string",
          description: "ID da versão em rascunho"
        }),
      required: ["version_id", "statement", "type"]
    },
    "update_question" => %{
      description:
        "Atualiza uma questão de uma versão em rascunho. " <>
          "Se options for omitido, as alternativas atuais são mantidas.",
      scope: @write_scope,
      properties:
        Map.put(@question_properties, "question_id", %{
          type: "string",
          description: "ID da questão"
        }),
      required: ["question_id"]
    },
    "delete_question" => %{
      description: "Remove uma questão de uma versão em rascunho.",
      scope: @write_scope,
      properties: %{"question_id" => %{type: "string", description: "ID da questão"}},
      required: ["question_id"]
    }
  }

  @doc "Definições no formato esperado por tools/list."
  def definitions do
    @tools
    |> Enum.sort_by(fn {name, _tool} -> name end)
    |> Enum.map(fn {name, tool} ->
      %{
        name: name,
        description: tool.description,
        inputSchema: %{
          type: "object",
          properties: tool.properties,
          required: tool.required,
          additionalProperties: false
        }
      }
    end)
  end

  @doc """
  Executa uma ferramenta em nome do usuário autenticado.

  Retorna `{:ok, resultado}` no formato de tools/call (incluindo erros de
  domínio, com `isError: true`) ou `{:error, :unknown_tool}`.
  """
  def call(name, args, user, scopes) do
    with {:ok, tool} <- Map.fetch(@tools, name),
         :ok <- check_scope(tool, scopes),
         :ok <- check_required(tool, args) do
      {:ok, run(name, args, user)}
    else
      :error -> {:error, :unknown_tool}
      {:tool_error, result} -> {:ok, result}
    end
  end

  defp check_scope(%{scope: nil}, _scopes), do: :ok

  defp check_scope(%{scope: scope}, scopes) do
    if scope in scopes do
      :ok
    else
      {:tool_error, tool_error(%{code: "insufficient_scope", required_scope: scope})}
    end
  end

  defp check_required(%{required: required}, args) do
    case Enum.reject(required, &Map.has_key?(args, &1)) do
      [] ->
        :ok

      missing ->
        {:tool_error,
         validation(["argumentos obrigatórios ausentes: " <> Enum.join(missing, ", ")])}
    end
  end

  defp run("list_quizzes", _args, user) do
    ok(%{quizzes: Enum.map(Quizzes.list_created(user), &Serializer.quiz/1)})
  end

  defp run("get_quiz", %{"quiz_id" => id}, user) do
    case Quizzes.get_owned_quiz(id, user) do
      {:ok, quiz} -> ok(Serializer.quiz(quiz))
      {:error, error} -> domain_error(error)
    end
  end

  defp run("create_quiz", args, user) do
    with {:ok, version} <- Quizzes.create_draft_quiz(user, Params.quiz(args)),
         {:ok, full} <- Quizzes.get_owned_version_full(version.id, user) do
      ok(Serializer.version(full))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("import_quiz", %{"data" => data}, user) when is_map(data) do
    case Quizzes.import_quiz(user, Jason.encode!(data)) do
      {:ok, version} -> ok(Serializer.version(version))
      {:error, error} -> domain_error(error)
    end
  end

  defp run("set_quiz_active", %{"quiz_id" => id, "active" => active}, user)
       when is_boolean(active) do
    with {:ok, quiz} <- Quizzes.get_owned_quiz(id, user),
         {:ok, _updated} <- Quizzes.set_quiz_active(quiz, active, user),
         {:ok, reloaded} <- Quizzes.get_owned_quiz(id, user) do
      ok(Serializer.quiz(reloaded))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("set_quiz_active", _args, _user) do
    validation(["active precisa ser true ou false"])
  end

  defp run("create_quiz_draft", %{"quiz_id" => id}, user) do
    with {:ok, quiz} <- Quizzes.get_owned_quiz(id, user),
         {:ok, version} <- Quizzes.ensure_draft(quiz, user),
         {:ok, full} <- Quizzes.get_owned_version_full(version.id, user) do
      ok(Serializer.version(full))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("get_quiz_version", %{"version_id" => id}, user) do
    case Quizzes.get_owned_version_full(id, user) do
      {:ok, version} -> ok(Serializer.version(version))
      {:error, error} -> domain_error(error)
    end
  end

  defp run("update_quiz_version", %{"version_id" => id} = args, user) do
    with {:ok, version} <- Quizzes.get_owned_version_full(id, user),
         {:ok, updated} <- Quizzes.update_draft(version, Params.quiz(args), user),
         {:ok, full} <- Quizzes.get_owned_version_full(updated.id, user) do
      ok(Serializer.version(full))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("validate_quiz_version", %{"version_id" => id}, user) do
    with {:ok, version} <- Quizzes.get_owned_version_full(id, user) do
      case Quizzes.validate_draft(version, user) do
        :ok -> ok(%{valid: true, errors: []})
        {:error, errors} when is_list(errors) -> ok(%{valid: false, errors: errors})
        {:error, error} -> domain_error(error)
      end
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("publish_quiz_version", %{"version_id" => id}, user) do
    with {:ok, version} <- Quizzes.get_owned_version_full(id, user),
         {:ok, published} <- Quizzes.publish(version, user),
         {:ok, full} <- Quizzes.get_owned_version_full(published.id, user) do
      ok(Serializer.version(full))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("create_question", %{"version_id" => id} = args, user) do
    with {:ok, version} <- Quizzes.get_owned_version_full(id, user),
         {:ok, options} <- Params.options(args),
         {:ok, question} <-
           Quizzes.upsert_question(version, Params.question(args), options || [], user) do
      ok(Serializer.question(question))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("update_question", %{"question_id" => id} = args, user) do
    with {:ok, question, version} <- Quizzes.get_owned_question(id, user),
         {:ok, requested_options} <- Params.options(args),
         options = requested_options || Enum.map(question.options, &Serializer.option_attrs/1),
         attrs = Map.put(Params.question(args), :id, question.id),
         {:ok, updated} <- Quizzes.upsert_question(version, attrs, options, user) do
      ok(Serializer.question(updated))
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run("delete_question", %{"question_id" => id}, user) do
    with {:ok, question, _version} <- Quizzes.get_owned_question(id, user),
         :ok <- Quizzes.delete_question(question, user) do
      ok(%{deleted: true, id: id})
    else
      {:error, error} -> domain_error(error)
    end
  end

  defp run(_name, _args, _user), do: validation(["argumentos inválidos"])

  defp ok(data) do
    %{
      content: [%{type: "text", text: Jason.encode!(data)}],
      structuredContent: data,
      isError: false
    }
  end

  # Espelha o mapeamento de erros de QuizProjectWeb.Api.Response.
  defp domain_error(error) when error in [:unauthorized, :not_found, :question_not_found] do
    tool_error(%{code: "not_found", message: "Recurso não encontrado"})
  end

  defp domain_error(:not_draft), do: conflict("version_not_editable")
  defp domain_error(:no_version), do: conflict("published_version_required")

  defp domain_error(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(fn
      %{message: message} when is_binary(message) -> message
      other -> Exception.message(other)
    end)
    |> Enum.uniq()
    |> validation()
  end

  defp domain_error(error) when is_binary(error), do: validation([error])
  defp domain_error(errors) when is_list(errors), do: validation(errors)

  defp domain_error(_error) do
    tool_error(%{code: "operation_failed", message: "Não foi possível concluir a operação"})
  end

  defp conflict(code) do
    tool_error(%{code: code, message: "A operação não é permitida no estado atual"})
  end

  defp validation(details) do
    tool_error(%{code: "validation_error", details: details})
  end

  defp tool_error(error) do
    %{
      content: [%{type: "text", text: Jason.encode!(%{error: error})}],
      structuredContent: %{error: error},
      isError: true
    }
  end
end
