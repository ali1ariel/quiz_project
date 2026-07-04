defmodule QuizProjectWeb.Router do
  use QuizProjectWeb, :router

  import QuizProjectWeb.UserAuth

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
    delete "/sair", AuthController, :logout

    live_session :public,
      on_mount: [{QuizProjectWeb.UserAuth, :mount_current_user}] do
      live "/q/:slug", QuizPublicLive
      live "/tentativa/:id", AttemptLive
      live "/tentativa/:id/resultado", ResultLive
    end
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
  end

  scope "/", QuizProjectWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/entrar", AuthController, :login_form
    post "/entrar", AuthController, :login
    get "/criar-conta", AuthController, :register_form
    post "/criar-conta", AuthController, :register
  end

  scope "/", QuizProjectWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{QuizProjectWeb.UserAuth, :ensure_authenticated}] do
      live "/painel", DashboardLive
      live "/quiz/:version_id/editar", QuizEditorLive
      live "/quiz/:quiz_id/gerenciar", QuizManageLive
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
