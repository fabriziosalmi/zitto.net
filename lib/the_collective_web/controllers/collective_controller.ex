defmodule TheCollectiveWeb.CollectiveController do
  @moduledoc """
  Controller for serving The Collective's minimal interface.
  
  This controller serves the static HTML interface for The Collective,
  optimized for CDN distribution and minimal server load.
  """
  
  use TheCollectiveWeb, :controller
  
  @doc """
  Serve The Collective's main interface.
  
  Returns the static HTML page that contains the entire client-side
  application for connecting to The Collective.
  """
  def index(conn, _params) do
    # Serve the static HTML directly from priv/static
    static_path = Application.app_dir(:the_collective, "priv/static/index.html")
    
    case File.read(static_path) do
      {:ok, content} ->
        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_resp(200, content)
      
      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "The Collective is not yet awakened.")
    end
  end
end
