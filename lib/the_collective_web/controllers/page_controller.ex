defmodule TheCollectiveWeb.PageController do
  use TheCollectiveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
