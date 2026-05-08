defmodule MixwaveWeb.PageController do
  use MixwaveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
