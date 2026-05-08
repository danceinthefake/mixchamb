defmodule Mixwave.Library do
  @moduledoc """
  The Library context — songs and comments.

  Songs are global-public per BRAINSTORM §6: every visitor sees every
  song. There's no per-song visibility flag in v1.
  """
  import Ecto.Query

  alias Mixwave.Library.{Song, Comment}
  alias Mixwave.Repo

  ## Songs

  @doc """
  Newest songs first. Preloads the uploader so the library page can
  show "by ayu-merak-42" without an N+1.
  """
  def list_songs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Song
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Songs uploaded by a specific anonymous user, newest first. Used by
  the manage page.
  """
  def list_user_songs(user_id) do
    Song
    |> where([s], s.user_id == ^user_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Fetches a single song with its uploader preloaded. Returns `nil` if
  not found.
  """
  def get_song(id), do: Repo.get(Song, id) |> preload_user()

  defp preload_user(nil), do: nil
  defp preload_user(%Song{} = song), do: Repo.preload(song, :user)

  @doc """
  Inserts a song. Used after the browser confirms it has PUT the file
  to R2 and we've HEAD-verified the object.
  """
  def create_song(attrs) do
    %Song{}
    |> Song.creation_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a song's editable fields (title/description/genre). Storage
  key and duration are owned by the upload flow and aren't editable.
  """
  def update_song(%Song{} = song, attrs) do
    song
    |> Song.edit_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a song. Comments cascade automatically. The R2 object is
  deleted by the caller (manage LiveView) since this context shouldn't
  reach into storage directly.
  """
  def delete_song(%Song{} = song), do: Repo.delete(song)

  ## Comments

  @doc """
  Comments for a song, oldest first. The composite index
  `(song_id, inserted_at)` keeps this cheap as comment counts grow.
  """
  def list_comments(song_id) do
    Comment
    |> where([c], c.song_id == ^song_id)
    |> order_by(asc: :inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Inserts a comment.
  """
  def create_comment(attrs) do
    %Comment{}
    |> Comment.creation_changeset(attrs)
    |> Repo.insert()
  end
end
