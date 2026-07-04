defmodule QuizProjectWeb.QuizPublicLive do
  @moduledoc """
  Página pública de um quiz (link compartilhável). Sempre serve a versão
  publicada mais recente. Cadastro é opcional para responder.
  """
  use QuizProjectWeb, :live_view

  alias QuizProject.Attempts
  alias QuizProject.Quizzes

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="pt-6 max-w-lg mx-auto w-full">
        <div class="card qcard bg-base-200 p-6 space-y-4">
          <div>
            <h1 class="text-2xl font-bold">{@version.name}</h1>
            <p :if={@version.description != ""} class="opacity-70 mt-1">{@version.description}</p>
            <div class="flex gap-2 mt-3 text-xs">
              <span class="badge badge-ghost rounded-full">
                {length(@version.questions)} questões
              </span>
              <span class="badge badge-ghost rounded-full">
                nota máxima {format_decimal(@version.total_points)}
              </span>
              <span
                :if={version_suffix(@version.version_number)}
                class="badge badge-ghost rounded-full"
              >
                {version_suffix(@version.version_number)}
              </span>
            </div>
          </div>

          <div :if={!@quiz.active} class="alert alert-warning rounded-2xl text-sm" id="closed-box">
            <.icon name="hero-lock-closed" class="size-5" />
            <span>As respostas para este quiz foram encerradas pelo criador.</span>
          </div>

          <div :if={@quiz.active && @in_progress} class="alert rounded-2xl text-sm" id="resume-box">
            <.icon name="hero-arrow-path" class="size-5" />
            <span>Você tem uma tentativa em andamento neste quiz.</span>
            <.link
              navigate={~p"/tentativa/#{@in_progress.id}"}
              class="btn btn-primary btn-sm rounded-full"
            >
              Continuar
            </.link>
          </div>

          <form
            :if={@quiz.active && !@in_progress}
            phx-submit="start"
            id="start-form"
            class="space-y-3"
          >
            <div>
              <label class="label text-sm mb-1" for="display-identity">
                Como prefere se identificar?
              </label>
              <input
                type="text"
                name="display_identity"
                id="display-identity"
                required
                maxlength="80"
                class="input input-bordered w-full rounded-full"
                placeholder="Nome, apelido ou código — é o que o criador do quiz verá"
              />
              <p class="text-xs opacity-60 mt-1">
                O criador do quiz vê apenas essa identificação, nunca os dados da sua conta.
              </p>
            </div>

            <div :if={@start_error} class="alert alert-error rounded-xl text-sm">{@start_error}</div>

            <button type="submit" id="start-attempt" class="btn btn-primary w-full rounded-full">
              Começar a responder
            </button>

            <p :if={!@current_user} class="text-xs opacity-60 text-center">
              Você está respondendo como participante anônimo.
              <.link navigate={~p"/entrar"} class="link">Entre na sua conta</.link>
              para poder continuar de outro dispositivo.
            </p>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(%{"slug" => slug}, _session, socket) do
    case Quizzes.get_public_by_slug(slug) do
      {:ok, {quiz, version}} ->
        participant = participant(socket)

        {:ok,
         assign(socket,
           quiz: quiz,
           version: version,
           in_progress: Attempts.find_in_progress(version, participant),
           start_error: nil
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Quiz não encontrado ou ainda não publicado.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("start", _params, %{assigns: %{quiz: %{active: false}}} = socket) do
    {:noreply, assign(socket, start_error: "As respostas para este quiz foram encerradas.")}
  end

  def handle_event("start", %{"display_identity" => identity}, socket) do
    case Attempts.start_attempt(socket.assigns.version, participant(socket), identity) do
      {:ok, attempt} ->
        {:noreply, push_navigate(socket, to: ~p"/tentativa/#{attempt.id}")}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply, assign(socket, start_error: "Informe como prefere se identificar.")}

      {:error, _} ->
        {:noreply, assign(socket, start_error: "Não foi possível iniciar a tentativa.")}
    end
  end

  defp participant(socket) do
    %{user: socket.assigns.current_user, token: socket.assigns.participant_token}
  end

  defp format_decimal(decimal) do
    decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
  end
end
