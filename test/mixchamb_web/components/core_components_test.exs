defmodule MixchambWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MixchambWeb.CoreComponents

  defp html(template), do: rendered_to_string(template)

  describe "button/1" do
    test "renders a <button> with the variant classes" do
      assigns = %{}
      out = html(~H|<.button variant="outline" type="submit">Go</.button>|)
      assert out =~ "<button"
      assert out =~ ~s(type="submit")
      assert out =~ "Go"
    end

    test "renders a <.link> when href / navigate / patch is given" do
      assigns = %{}
      assert html(~H|<.button href="/x">L</.button>|) =~ ~s(<a href="/x")
      assert html(~H|<.button navigate="/y" variant="ghost">L</.button>|) =~ ~s(href="/y")
    end
  end

  describe "flash/1" do
    test "renders info and error flashes, hidden when empty" do
      assigns = %{}
      assert html(~H|<.flash kind={:info} flash={%{"info" => "hi"}} />|) =~ "hi"
      out = html(~H|<.flash kind={:error} title="Oops" flash={%{"error" => "bad"}} />|)
      assert out =~ "Oops" and out =~ "bad"
      assert html(~H|<.flash kind={:info} flash={%{}} />|) == ""
      assert html(~H|<.flash kind={:info} id="x">slot</.flash>|) =~ "slot"
    end
  end

  describe "input/1" do
    test "every input type renders" do
      form = to_form(%{"name" => "n", "ok" => true, "pick" => "b", "note" => "t"}, as: :f)
      assigns = %{form: form}

      out =
        html(~H"""
        <.input field={@form[:name]} label="Name" placeholder="p" />
        <.input field={@form[:ok]} type="checkbox" label="Ok" />
        <.input field={@form[:pick]} type="select" label="Pick" prompt="—" options={[a: "a", b: "b"]} />
        <.input field={@form[:note]} type="textarea" label="Note" />
        <.input field={@form[:name]} type="hidden" />
        <.input name="raw" value="v" type="text" label="Raw" errors={["is bad"]} />
        <.input name="c" value="1" type="checkbox" checked={true} class="custom" />
        """)

      assert out =~ ~s(name="f[name]")
      assert out =~ ~s(type="checkbox")
      assert out =~ "<select"
      assert out =~ "<textarea"
      assert out =~ ~s(type="hidden")
      assert out =~ "is bad"
      assert out =~ "custom"
    end

    test "form field errors surface only once the input was used" do
      changeset =
        {%{}, %{title: :string}}
        |> Ecto.Changeset.cast(%{"title" => ""}, [:title])
        |> Ecto.Changeset.validate_required([:title])
        |> Map.put(:action, :validate)

      form = to_form(changeset, as: :thing)
      assigns = %{form: form}
      assert html(~H|<.input field={@form[:title]} label="T" />|) =~ "can&#39;t be blank"
    end
  end

  describe "header / table / list / icon" do
    test "header with subtitle + actions" do
      assigns = %{}

      out =
        html(~H"""
        <.header>
          Title
          <:subtitle>Sub</:subtitle>
          <:actions><button>A</button></:actions>
        </.header>
        """)

      assert out =~ "Title" and out =~ "Sub" and out =~ "<button>A</button>"
    end

    test "table renders rows, columns, row_click and actions" do
      assigns = %{rows: [%{id: 1, name: "one"}, %{id: 2, name: "two"}]}

      out =
        html(~H"""
        <.table id="t" rows={@rows} row_click={fn r -> "go-#{r.id}" end} row_id={&"row-#{&1.id}"}>
          <:col :let={r} label="Name">{r.name}</:col>
          <:action :let={r}><a href={"/#{r.id}"}>edit</a></:action>
        </.table>
        """)

      assert out =~ "Name" and out =~ "one" and out =~ "two"
      assert out =~ ~s(id="row-1")
      assert out =~ ~s(phx-click="go-2")
      assert out =~ "edit"
    end

    test "table over a stream uses the stream id" do
      stream = Phoenix.LiveView.LiveStream.new(:rows, 0, [%{id: 1, name: "s"}], [])
      assigns = %{stream: stream}

      out =
        html(~H"""
        <.table id="s" rows={@stream}>
          <:col :let={{_id, r}} label="N">{r.name}</:col>
        </.table>
        """)

      assert out =~ "rows-1"
    end

    test "list + icon" do
      assigns = %{}

      out =
        html(~H"""
        <.list>
          <:item title="K">V</:item>
        </.list>
        <.icon name="hero-x-mark" class="size-6" />
        """)

      assert out =~ "K" and out =~ "V" and out =~ "hero-x-mark size-6"
    end
  end

  describe "JS + translations" do
    test "show/hide build JS commands" do
      assert %Phoenix.LiveView.JS{ops: [["show", _]]} = show("#a")
      assert %Phoenix.LiveView.JS{ops: [["hide", _]]} = hide("#a")
    end

    test "translate_error handles count and plain messages" do
      assert translate_error({"should be at least %{count} character(s)", count: 3}) =~ "3"
      assert translate_error({"is invalid", []}) == "is invalid"

      assert translate_errors([name: {"is invalid", []}, other: {"x", []}], :name) == [
               "is invalid"
             ]
    end
  end
end
