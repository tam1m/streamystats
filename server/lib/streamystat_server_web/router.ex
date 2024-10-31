defmodule StreamystatServerWeb.Router do
  use StreamystatServerWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth do
    plug(StreamystatServerWeb.AuthPlug)
  end

  scope "/api", StreamystatServerWeb do
    pipe_through(:api)

    # Public routes
    post("/login", AuthController, :login)
    get("/health", HealthController, :check)
    get("/servers", ServerController, :index)
    get("/servers/:id", ServerController, :show)
    post("/servers", ServerController, :create)

    # Protected routes
    scope "/servers/:server_id", as: :protected do
      pipe_through(:auth)

      delete("/", ServerController, :delete)
      get("/me", UserController, :me)
      post("/sync", SyncController, :partial_sync)
      post("/sync/full", SyncController, :full_sync)
      post("/sync/users", SyncController, :sync_users)
      post("/sync/libraries", SyncController, :sync_libraries)
      post("/sync/items", SyncController, :sync_items)
      post("/sync/playback-statistics", SyncController, :sync_playback_stats)
      get("/statistics", StatisticsController, :index)
      get("/statistics/history", StatisticsController, :history)
      resources("/users", UserController, only: [:index, :show])
    end
  end

  if Application.compile_env(:streamystat_server, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: StreamystatServerWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
