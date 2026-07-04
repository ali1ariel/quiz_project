defmodule QuizProject.Accounts do
  use Ash.Domain

  resources do
    resource QuizProject.Accounts.User do
      define :register_user, action: :register
      define :get_user_by_id, action: :read, get_by: [:id]
    end
  end
end
