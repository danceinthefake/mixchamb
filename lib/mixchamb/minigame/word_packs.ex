defmodule Mixchamb.MiniGame.WordPacks do
  @moduledoc """
  Preset word lists for Pictionary (mini-game.md §4).

  Each pack is a flat list of single- or multi-word answers. The
  drawer is offered three random candidates from the session's pack
  at the start of their turn and picks one. Words are sampled
  without repeat within a game; when a pack runs dry the sampler
  refills (repeats allowed) rather than ending the game early
  (spec §7 "word pack exhausted").

  Packs are intentionally drawable-by-anyone — concrete nouns and
  well-known phrases, nothing that needs domain knowledge. A
  `:custom` host-pasted pack is deferred polish (spec §9).
  """

  @packs %{
    "general" => ~w(
      apple bicycle mountain umbrella guitar rainbow island volcano
      lighthouse penguin rocket sandwich telescope waterfall windmill
      anchor balloon cactus dragon ladder pyramid scarecrow snowman
      treasure violin whale igloo kite robot
    ) ++ ["ice cream", "hot air balloon", "shooting star", "police car"],
    "animals" => ~w(
      elephant giraffe kangaroo octopus penguin dolphin hedgehog
      flamingo crocodile butterfly squirrel jellyfish peacock tortoise
      chameleon rhinoceros seahorse owl koala panda lobster narwhal
      platypus walrus
    ),
    "movies" => [
      "Star Wars",
      "Jurassic Park",
      "The Lion King",
      "Finding Nemo",
      "Toy Story",
      "Harry Potter",
      "The Matrix",
      "Frozen",
      "Titanic",
      "Jaws",
      "Up",
      "Avatar",
      "Shrek",
      "Ghostbusters",
      "Back to the Future"
    ],
    "office" => [
      "stand-up meeting",
      "coffee break",
      "whiteboard",
      "deadline",
      "spreadsheet",
      "video call",
      "sticky note",
      "keyboard",
      "printer jam",
      "swivel chair",
      "burndown chart",
      "code review",
      "merge conflict",
      "retro board",
      "rubber duck"
    ]
  }

  @default_pack "general"

  @doc "All pack ids, for the lobby picker."
  def ids, do: Map.keys(@packs) |> Enum.sort()

  @doc "The default pack id used when a session hasn't picked one."
  def default, do: @default_pack

  @doc "True when `id` names a real pack."
  def valid?(id) when is_binary(id), do: Map.has_key?(@packs, id)
  def valid?(_), do: false

  @doc "The raw word list for a pack (or the default pack's list for an unknown id)."
  def words(id) when is_binary(id), do: Map.get(@packs, id, @packs[@default_pack])

  @doc """
  Draw `count` distinct candidate words from `pack`, excluding any in
  `used`. Falls back to allowing repeats when the remaining pool is
  smaller than `count` (spec §7 pack-exhausted refill).
  """
  def sample(pack, count, used \\ []) when is_binary(pack) and is_integer(count) do
    sample_from(words(pack), count, used)
  end

  @doc """
  Same no-repeat-then-refill draw as `sample/3`, but from an arbitrary
  word list — used for the host's `:custom` pack (spec §9).
  """
  def sample_from(all, count, used \\ []) when is_list(all) and is_integer(count) do
    remaining = all -- used
    pool = if length(remaining) >= count, do: remaining, else: all
    pool |> Enum.shuffle() |> Enum.take(count)
  end
end
