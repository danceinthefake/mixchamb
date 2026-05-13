defmodule MixwaveWeb.Plugs.SecurityHeadersTest do
  use MixwaveWeb.ConnCase, async: false

  alias MixwaveWeb.Plugs.SecurityHeaders

  describe "in dev/test (vite_host configured)" do
    # The test env has `:live_vue, :vite_host` set to localhost:5173,
    # so the plug emits the dev policy here. We don't bother
    # toggling Application env across tests — the prod policy is
    # exercised by direct string assertions instead.

    test "emits a Content-Security-Policy header" do
      conn = SecurityHeaders.call(build_conn(:get, "/"), [])
      assert [header] = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert header =~ "default-src 'self'"
    end

    test "csp_nonce assign is nil in dev (unsafe-inline already covers it)" do
      conn = SecurityHeaders.call(build_conn(:get, "/"), [])
      assert conn.assigns.csp_nonce == nil
    end

    test "dev policy allows 'unsafe-inline' + 'unsafe-eval' for scripts" do
      conn = SecurityHeaders.call(build_conn(:get, "/"), [])
      [header] = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert header =~ "'unsafe-inline'"
      assert header =~ "'unsafe-eval'"
    end

    test "policy allowlists the Tone.js sample CDNs in connect-src" do
      conn = SecurityHeaders.call(build_conn(:get, "/"), [])
      [header] = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert header =~ "https://tonejs.github.io"
      assert header =~ "https://nbrosowsky.github.io"
    end

    test "policy locks frame-ancestors and object-src" do
      conn = SecurityHeaders.call(build_conn(:get, "/"), [])
      [header] = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert header =~ "frame-ancestors 'none'"
      assert header =~ "object-src 'none'"
    end
  end

  describe "end-to-end through the :browser pipeline" do
    test "GET / serves the header", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert [header] = Plug.Conn.get_resp_header(conn, "content-security-policy")
      assert header =~ "default-src 'self'"
    end
  end
end
