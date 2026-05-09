defmodule Mixwave.Chambers do
  @moduledoc """
  The Chambers context — secret rooms identified by an unguessable
  slug.

  Each chamber gets a random URL token at creation; anyone with
  the resulting link can join. A chamber starts in a "grace"
  state (`activated_at: nil`); the first time someone other than
  the creator joins, `mark_active/1` flips it to active. If
  nobody else joins within 5 minutes,
  `Mixwave.Studio.Chamber` deletes the row.

  This module is the persistence layer; the runtime audio + life-
  cycle live in `Mixwave.Studio.Chamber`.
  """

  alias Mixwave.Chambers.Chamber
  alias Mixwave.Repo

  @doc """
  Creates a new chamber owned by `creator_user_id`. The slug is
  generated automatically.
  """
  def create_chamber(creator_user_id) when is_binary(creator_user_id) do
    %Chamber{}
    |> Chamber.creation_changeset(%{
      slug: generate_slug(),
      creator_user_id: creator_user_id
    })
    |> Repo.insert()
  end

  @doc """
  Looks up a chamber by its URL slug. Returns nil if not found.
  """
  def find_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Chamber, slug: slug)
  end

  @doc """
  Marks a chamber active — called the first time a non-creator
  joins. No-op if already active.
  """
  def mark_active(%Chamber{activated_at: nil} = chamber) do
    chamber
    |> Chamber.activation_changeset()
    |> Repo.update()
  end

  def mark_active(%Chamber{} = chamber), do: {:ok, chamber}

  @doc """
  Permanently deletes a chamber row. Called when the chamber's
  GenServer terminates because nobody but the creator showed up.
  """
  def delete(%Chamber{} = chamber), do: Repo.delete(chamber)

  # Generates a ~64-bit URL-safe token. 8 random bytes encode to 11
  # url-base64 chars. Collision probability stays negligible at any
  # realistic chamber count.
  defp generate_slug do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
