defmodule QuizProjectWeb.Router do
  use QuizProjectWeb, :router

  import QuizProjectWeb.UserAuth

  get "/health", QuizProjectWeb.HealthController, :index

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QuizProjectWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :ensure_participant_token
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug QuizProjectWeb.ApiAuth, :fetch_api_user
  end

  scope "/", QuizProjectWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/api/docs", PageController, :api_docs
    get "/attempt/:id/og.png", OgController, :result
    delete "/logout", AuthController, :logout

    live_session :public,
      on_mount: [{QuizProjectWeb.UserAuth, :mount_current_user}] do
      live "/q/:slug", QuizPublicLive
      live "/attempt/:id", AttemptLive
      live "/attempt/:id/result", ResultLive
    end
  end

  scope "/api", QuizProjectWeb.Api do
    pipe_through :api

    get "/openapi.json", OpenApiController, :show
  end

  scope "/api/v1", QuizProjectWeb.Api do
    pipe_through :api

    post "/auth/tokens", AuthController, :create
  end

  scope "/api/v1", QuizProjectWeb.Api do
    pipe_through [:api, :api_authenticated]

    delete "/auth/token", AuthController, :delete

    get "/quizzes", QuizController, :index
    post "/quizzes", QuizController, :create
    post "/quizzes/import", QuizController, :import
    get "/quizzes/:id", QuizController, :show
    patch "/quizzes/:id", QuizController, :update
    post "/quizzes/:id/drafts", QuizController, :create_draft

    get "/quiz-versions/:id", VersionController, :show
    patch "/quiz-versions/:id", VersionController, :update
    post "/quiz-versions/:id/questions", QuestionController, :create
    post "/quiz-versions/:id/validate", VersionController, :validate
    post "/quiz-versions/:id/publish", VersionController, :publish

    patch "/questions/:id", QuestionController, :update
    delete "/questions/:id", QuestionController, :delete

    post "/study/import", StudyController, :import
  end

  scope "/api", QuizProjectWeb do
    pipe_through [:api, :api_authenticated]

    post "/mcp", McpController, :handle
    get "/mcp", McpController, :method_not_allowed
    delete "/mcp", McpController, :method_not_allowed
  end

  scope "/", QuizProjectWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/login", AuthController, :login_form
    post "/login", AuthController, :login
    get "/register", AuthController, :register_form
    post "/register", AuthController, :register
  end

  scope "/", QuizProjectWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/contents/:id/book.css", BookStyleController, :show
    get "/contents/:id/images/*path", BookImageController, :show

    live_session :authenticated,
      on_mount: [
        {QuizProjectWeb.UserAuth, :ensure_authenticated},
        {QuizProjectWeb.UserAuth, :notify_attempts},
        {QuizProjectWeb.UserAuth, :notify_loose_captures}
      ] do
      live "/dashboard", DashboardLive
      live "/today", KanbanLive
      live "/settings", SettingsLive
      live "/quiz/:version_id/edit", QuizEditorLive
      live "/quiz/:quiz_id/manage", QuizManageLive
      live "/quiz/:quiz_id/evolution", QuizEvolutionLive

      live "/study", AdaptiveStudyLive.Index
      live "/study/new", AdaptiveStudyLive.Upload
      live "/study/:id/curate", AdaptiveStudyLive.Curate, :curate
      live "/study/:id/curate/map", AdaptiveStudyLive.Curate, :map

      # Leitura é seção própria: ciclo de vida, volume e estado não têm
      # interseção com a curadoria. `/new` vem antes de `/:id` porque o
      # roteador casa na ordem em que as rotas são declaradas.
      live "/contents", ContentsLive.Index
      live "/contents/new", ContentsLive.Upload
      live "/contents/:id", ContentsLive.Read
      live "/contents/:id/:chapter", ContentsLive.Read, :chapter

      # Gerenciamento pessoal por categorias e itens. `/ranking` e `/items` vêm
      # antes de `/:id` pelo mesmo motivo do grupo acima: o roteador casa na
      # ordem em que as rotas são declaradas.
      live "/priorities", PrioritiesLive.Index
      live "/priorities/ranking", PrioritiesLive.Ranking
      live "/priorities/items", PrioritiesLive.Browse
      live "/priorities/:id", PrioritiesLive.Show
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:quiz_project, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: QuizProjectWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
