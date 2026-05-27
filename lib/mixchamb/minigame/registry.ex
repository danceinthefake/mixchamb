defmodule Mixchamb.MiniGame.Registry do
  @moduledoc """
  Atom/string key → game-module lookup (mini-game.md §1). v1 ships a
  single game; a second game is one extra entry here (plus its module
  and Vue stage component). The framework reads this registry for the
  lobby picker and to dispatch actions to the chosen game.
  """

  alias Mixchamb.MiniGame.Pictionary
  alias Mixchamb.MiniGame.GarticPhone
  alias Mixchamb.MiniGame.TwoTruths

  @games %{
    "pictionary" => Pictionary,
    "gartic_phone" => GarticPhone,
    "two_truths" => TwoTruths
  }

  @default "pictionary"

  @doc "All registry keys, for the lobby game picker."
  def keys, do: Map.keys(@games) |> Enum.sort()

  @doc "The default game selected in a fresh lobby."
  def default, do: @default

  @doc "True when `key` names a registered game."
  def valid?(key) when is_binary(key), do: Map.has_key?(@games, key)
  def valid?(_), do: false

  @doc "The module implementing `key` (or the default game's module for an unknown key)."
  def module(key) when is_binary(key), do: Map.get(@games, key, @games[@default])

  @doc "Human label for a game key, used in the picker + page title."
  def label("pictionary"), do: "Pictionary"
  def label("gartic_phone"), do: "Gartic Phone"
  def label("two_truths"), do: "Two Truths & a Lie"
  def label(other), do: String.capitalize(other)
end
