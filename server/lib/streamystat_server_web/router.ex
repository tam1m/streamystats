defmodule StreamystatServerWeb.Router do
  use StreamystatServerWeb, :router
  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveDashboard.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth do
    plug(StreamystatServerWeb.AuthPlug)
  end

  pipeline :admin_auth do
    plug(StreamystatServerWeb.AdminAuthPlug)
  end

  scope "/" do
    pipe_through([:fetch_session, :protect_from_forgery])
    live_dashboard("/dashboard", metrics: StreamystatServerWeb.Telemetry)
  end

  scope "/api", StreamystatServerWeb do
    pipe_through(:api)

    # Public routes
    post("/login", AuthController, :login)
    get("/health", HealthController, :check)
    get("/servers", ServerController, :index)
    get("/servers/:id", ServerController, :show)
    post("/servers", ServerController, :create)

    # Admin routes
    scope "/admin", as: :admin do
      pipe_through(:admin_auth)

      delete("/servers/:server_id", ServerController, :delete)
      post("/servers/:server_id/sync", SyncController, :partial_sync)
      post("/servers/:server_id/sync/full", SyncController, :full_sync)
      post("/servers/:server_id/sync/users", SyncController, :sync_users)
      post("/servers/:server_id/sync/libraries", SyncController, :sync_libraries)
      post("/servers/:server_id/sync/items", SyncController, :sync_items)
      post("/servers/:server_id/sync/playback-statistics", SyncController, :sync_playback_stats)
      get("/servers/:server_id/sync/tasks", SyncController, :list_tasks)
      get("/servers/:server_id/sync/tasks/:task_id", SyncController, :show_task)
      get("/servers/:server_id/activities", ActivityController, :index)
    end

    # Protected routes
    scope "/servers/:server_id", as: :protected do
      pipe_through(:auth)

      get("/me", UserController, :me)
      get("/statistics", UserStatisticsController, :index)
      get("/statistics/history", UserStatisticsController, :history)
      get("/statistics/items", UserStatisticsController, :items)
      get("/statistics/library", UserStatisticsController, :library_stats)

      resources("/users", UserController, only: [:index, :show])
    end
  end
end
