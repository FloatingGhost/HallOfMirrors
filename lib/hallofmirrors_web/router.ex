defmodule HallofmirrorsWeb.Router do
  use HallofmirrorsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HallofmirrorsWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/accounts", AccountController, :create
    get "/accounts/:id", AccountController, :edit_form
    post "/accounts/:id", AccountController, :edit
  end

  # Other scopes may use custom stacks.
  # scope "/api", HallofmirrorsWeb do
  #   pipe_through :api
  # end
end
