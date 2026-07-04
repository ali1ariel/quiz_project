defmodule QuizProjectWeb.SettingsLive do
  @moduledoc "Configurações de perfil, senha e credenciais de API do usuário."

  use QuizProjectWeb, :live_view

  alias QuizProject.Accounts

  @tabs ~w(profile security tokens)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_nav={:account} wide>
      <div id="settings-page" class="grid gap-8 lg:grid-cols-[15rem_minmax(0,1fr)]">
        <aside class="space-y-5">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">Área pessoal</p>
            <h1 class="mt-2 text-3xl font-bold tracking-tight">Conta e API</h1>
            <p class="mt-2 text-sm leading-6 opacity-60">
              Perfil, senha e credenciais para integrações.
            </p>
          </div>

          <nav
            id="settings-tabs"
            class="grid grid-cols-3 gap-2 lg:grid-cols-1"
            aria-label="Conta e API"
          >
            <button
              id="settings-tab-profile"
              type="button"
              phx-click="switch_tab"
              phx-value-tab="profile"
              class={tab_class(@tab == "profile")}
            >
              <.icon name="hero-user-circle" class="size-5" />
              <span>Perfil</span>
            </button>
            <button
              id="settings-tab-security"
              type="button"
              phx-click="switch_tab"
              phx-value-tab="security"
              class={tab_class(@tab == "security")}
            >
              <.icon name="hero-lock-closed" class="size-5" />
              <span>Segurança</span>
            </button>
            <button
              id="settings-tab-tokens"
              type="button"
              phx-click="switch_tab"
              phx-value-tab="tokens"
              class={tab_class(@tab == "tokens")}
            >
              <.icon name="hero-key" class="size-5" />
              <span>Tokens</span>
            </button>
          </nav>
        </aside>

        <div class="min-w-0">
          <section
            :if={@tab == "profile"}
            id="profile-settings"
            class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8"
          >
            <div class="mb-7 flex items-start gap-4">
              <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-identification" class="size-6" />
              </span>
              <div>
                <h2 class="text-xl font-bold">Dados do perfil</h2>
                <p class="mt-1 text-sm leading-6 opacity-60">
                  Seu e-mail é usado para entrar. Esses dados nunca são revelados aos criadores dos
                  quizzes que você responde.
                </p>
              </div>
            </div>

            <.form for={@profile_form} id="profile-form" phx-submit="save_profile" class="space-y-5">
              <.input
                field={@profile_form[:name]}
                type="text"
                label="Nome"
                autocomplete="name"
                maxlength="120"
                placeholder="Como devemos chamar você?"
              />
              <.input
                field={@profile_form[:email]}
                type="email"
                label="E-mail"
                autocomplete="email"
                required
              />
              <div class="flex justify-end pt-2">
                <button
                  id="save-profile"
                  type="submit"
                  class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:-translate-y-0.5 hover:shadow-lg disabled:cursor-wait disabled:opacity-60"
                  phx-disable-with="Salvando…"
                >
                  Salvar perfil
                </button>
              </div>
            </.form>
          </section>

          <section
            :if={@tab == "security"}
            id="security-settings"
            class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8"
          >
            <div class="mb-7 flex items-start gap-4">
              <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-shield-check" class="size-6" />
              </span>
              <div>
                <h2 class="text-xl font-bold">Alterar senha</h2>
                <p class="mt-1 text-sm leading-6 opacity-60">
                  Confirme sua senha atual antes de definir uma nova senha com pelo menos 8 caracteres.
                </p>
              </div>
            </div>

            <.form
              for={@password_form}
              id="password-form"
              phx-submit="change_password"
              class="space-y-5"
            >
              <.input
                field={@password_form[:current_password]}
                type="password"
                label="Senha atual"
                autocomplete="current-password"
                required
              />
              <div class="grid gap-5 sm:grid-cols-2">
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="Nova senha"
                  autocomplete="new-password"
                  minlength="8"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirmar nova senha"
                  autocomplete="new-password"
                  minlength="8"
                  required
                />
              </div>
              <div class="flex justify-end pt-2">
                <button
                  id="change-password"
                  type="submit"
                  class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:-translate-y-0.5 hover:shadow-lg disabled:cursor-wait disabled:opacity-60"
                  phx-disable-with="Alterando…"
                >
                  Alterar senha
                </button>
              </div>
            </.form>
          </section>

          <section :if={@tab == "tokens"} id="token-settings" class="space-y-5">
            <div class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
              <div class="flex flex-col justify-between gap-5 sm:flex-row sm:items-start">
                <div class="flex items-start gap-4">
                  <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-primary/10 text-primary">
                    <.icon name="hero-command-line" class="size-6" />
                  </span>
                  <div>
                    <h2 class="text-xl font-bold">Tokens de API</h2>
                    <p class="mt-1 max-w-2xl text-sm leading-6 opacity-60">
                      Use tokens em scripts, integrações e futuros servidores MCP. Cada segredo é
                      mostrado uma única vez.
                    </p>
                    <.link
                      id="token-api-docs-link"
                      href={~p"/api/docs"}
                      target="_blank"
                      rel="noreferrer"
                      class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                    >
                      Abrir documentação da API <.icon name="hero-arrow-up-right" class="size-3.5" />
                    </.link>
                  </div>
                </div>
                <span class="w-fit rounded-full bg-base-200 px-3 py-1 text-xs font-semibold">
                  {@token_count} {if @token_count == 1, do: "token", else: "tokens"}
                </span>
              </div>

              <.form
                for={@token_form}
                id="token-form"
                phx-submit="create_token"
                class="mt-7 flex flex-col gap-3 sm:flex-row sm:items-end"
              >
                <div class="flex-1">
                  <.input
                    field={@token_form[:name]}
                    type="text"
                    label="Nome do novo token"
                    maxlength="100"
                    placeholder="Ex.: Automação pessoal"
                    required
                  />
                </div>
                <button
                  id="create-token"
                  type="submit"
                  class="mb-2 shrink-0 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:-translate-y-0.5 hover:shadow-lg disabled:cursor-wait disabled:opacity-60"
                  phx-disable-with="Criando…"
                >
                  Criar token
                </button>
              </.form>
            </div>

            <div
              :if={@new_token}
              id="new-token-panel"
              class="rounded-3xl border border-success/40 bg-success/10 p-6 sm:p-7"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="font-bold text-success">Token criado</p>
                  <p class="mt-1 text-sm leading-6 opacity-70">
                    Copie agora. Por segurança, ele não poderá ser exibido novamente.
                  </p>
                </div>
                <button
                  id="close-new-token"
                  type="button"
                  phx-click="close_new_token"
                  class="rounded-full p-2 opacity-60 transition hover:bg-base-100 hover:opacity-100"
                  aria-label="Fechar"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>
              <div class="mt-4 flex flex-col gap-3 sm:flex-row">
                <code
                  id="new-token-value"
                  class="min-w-0 flex-1 overflow-x-auto rounded-2xl bg-neutral px-4 py-3 text-sm text-neutral-content"
                >{@new_token.value}</code>
                <button
                  id={"copy-new-token-#{@new_token.id}"}
                  type="button"
                  phx-hook=".CopyToken"
                  phx-update="ignore"
                  data-token={@new_token.value}
                  class="rounded-full border border-success/50 px-5 py-2.5 text-sm font-semibold text-success transition hover:bg-success hover:text-success-content"
                >
                  Copiar token
                </button>
              </div>
            </div>

            <div class="rounded-3xl border border-base-300 bg-base-100 p-3 shadow-sm sm:p-5">
              <div id="api-token-list" phx-update="stream" class="space-y-2">
                <div
                  id="tokens-empty"
                  class="hidden only:block rounded-2xl border border-dashed border-base-300 px-6 py-12 text-center"
                >
                  <.icon name="hero-key" class="mx-auto size-8 opacity-30" />
                  <p class="mt-3 font-semibold">Nenhum token criado</p>
                  <p class="mt-1 text-sm opacity-55">Crie um acima quando precisar integrar a API.</p>
                </div>

                <article
                  :for={{dom_id, token} <- @streams.api_tokens}
                  id={dom_id}
                  class="group flex flex-col gap-4 rounded-2xl px-4 py-4 transition hover:bg-base-200 sm:flex-row sm:items-center"
                >
                  <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-base-200 text-primary group-hover:bg-base-100">
                    <.icon name="hero-key" class="size-5" />
                  </span>
                  <div class="min-w-0 flex-1">
                    <p class="truncate font-semibold">{token.name}</p>
                    <p class="mt-1 text-xs opacity-55">
                      Criado em {format_datetime(token.inserted_at)} · {last_used_label(
                        token.last_used_at
                      )}
                    </p>
                    <div class="mt-2 flex flex-wrap gap-1.5">
                      <span
                        :for={scope <- token.scopes}
                        class="rounded-full bg-base-200 px-2.5 py-1 font-mono text-[0.68rem] opacity-70"
                      >
                        {scope}
                      </span>
                    </div>
                  </div>
                  <button
                    id={"revoke-token-#{token.id}"}
                    type="button"
                    phx-click="revoke_token"
                    phx-value-id={token.id}
                    data-confirm="Revogar este token? Integrações que o utilizam perderão o acesso imediatamente."
                    class="w-fit rounded-full px-4 py-2 text-sm font-semibold text-error transition hover:bg-error/10"
                  >
                    Revogar
                  </button>
                </article>
              </div>
            </div>
          </section>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToken">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              await navigator.clipboard.writeText(this.el.dataset.token)
              this.el.textContent = "Copiado!"
              window.setTimeout(() => { this.el.textContent = "Copiar token" }, 1800)
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    tokens = Accounts.list_api_tokens(user)

    {:ok,
     socket
     |> assign(:page_title, "Conta e API - Quizzes")
     |> assign(:tab, tab_from_params(params))
     |> assign(:profile_form, profile_form(user))
     |> assign(:password_form, password_form())
     |> assign(:token_form, token_form())
     |> assign(:new_token, nil)
     |> assign(:token_count, length(tokens))
     |> stream(:api_tokens, tokens, dom_id: &"api-token-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, tab_from_params(params))}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}

  def handle_event("save_profile", %{"profile" => params}, socket) do
    attrs = %{
      name: blank_to_nil(params["name"]),
      email: String.trim(params["email"] || "")
    }

    case Accounts.update_profile(socket.assigns.current_user, attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:profile_form, profile_form(user))
         |> put_flash(:info, "Perfil atualizado com sucesso.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, humanize_error(error))}
    end
  end

  def handle_event("change_password", %{"password" => params}, socket) do
    password = params["password"] || ""

    if password != (params["password_confirmation"] || "") do
      {:noreply, put_flash(socket, :error, "A confirmação da nova senha não confere.")}
    else
      case Accounts.change_password(
             socket.assigns.current_user,
             params["current_password"] || "",
             password
           ) do
        {:ok, user} ->
          {:noreply,
           socket
           |> assign(:current_user, user)
           |> assign(:password_form, password_form())
           |> put_flash(:info, "Senha alterada com sucesso.")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, humanize_error(error))}
      end
    end
  end

  def handle_event("create_token", %{"token" => params}, socket) do
    name = params["name"] |> blank_to_nil()

    if is_nil(name) do
      {:noreply, put_flash(socket, :error, "Dê um nome ao token.")}
    else
      case Accounts.issue_api_token(socket.assigns.current_user, %{name: name}) do
        {:ok, raw_token, token} ->
          {:noreply,
           socket
           |> assign(:new_token, %{id: token.id, value: raw_token})
           |> assign(:token_form, token_form())
           |> update(:token_count, &(&1 + 1))
           |> stream_insert(:api_tokens, token, at: 0)}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, humanize_error(error))}
      end
    end
  end

  def handle_event("close_new_token", _params, socket) do
    {:noreply, assign(socket, :new_token, nil)}
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    case Accounts.revoke_api_token(id, socket.assigns.current_user) do
      {:ok, token} ->
        {:noreply,
         socket
         |> stream_delete(:api_tokens, token)
         |> update(:token_count, &max(&1 - 1, 0))
         |> put_flash(:info, "Token revogado.")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Token não encontrado.")}
    end
  end

  defp profile_form(user) do
    to_form(%{"name" => user.name || "", "email" => to_string(user.email)}, as: :profile)
  end

  defp password_form do
    to_form(
      %{"current_password" => "", "password" => "", "password_confirmation" => ""},
      as: :password
    )
  end

  defp token_form, do: to_form(%{"name" => ""}, as: :token)

  defp tab_from_params(%{"tab" => tab}) when tab in @tabs, do: tab
  defp tab_from_params(_params), do: "profile"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp humanize_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(fn
      %{message: message} when is_binary(message) -> message
      other -> Exception.message(other)
    end)
    |> Enum.uniq()
    |> Enum.join(". ")
  end

  defp humanize_error(error), do: Exception.message(error)

  defp tab_class(active?) do
    [
      "flex items-center justify-center gap-2 rounded-2xl px-3 py-3 text-sm font-semibold transition lg:justify-start",
      if(active?,
        do: "bg-primary text-primary-content shadow-sm",
        else: "text-base-content/60 hover:bg-base-200 hover:text-base-content"
      )
    ]
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y às %H:%M")
  end

  defp last_used_label(nil), do: "ainda não utilizado"
  defp last_used_label(datetime), do: "último uso em #{format_datetime(datetime)}"
end
