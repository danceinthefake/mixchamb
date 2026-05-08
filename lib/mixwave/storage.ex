defmodule Mixwave.Storage do
  @moduledoc """
  Cloudflare R2 (S3-compatible) wrapper.

  Upload pattern (BRAINSTORM §4, Pattern A): the browser asks Phoenix
  for a short-lived presigned PUT URL, then PUTs the file *directly*
  to R2. Phoenix never sees the bytes — Fly egress stays at zero.

  After the browser reports success, we `head/1` the object to verify
  size + content-type before inserting the `songs` row. Aborted
  uploads leave orphan R2 objects; the `Mixwave.Workers.OrphanSweeper`
  reaps those (third flagship OTP demo).

  ## Configuration (runtime.exs from env)

    - `R2_ENDPOINT_HOST`     e.g. `<account_id>.r2.cloudflarestorage.com`
    - `R2_ACCESS_KEY_ID`     R2 API token access key
    - `R2_SECRET_ACCESS_KEY` R2 API token secret
    - `R2_BUCKET`            bucket name

  The bucket needs CORS configured to allow `PUT`, `GET`, `HEAD` from
  the app's origin — set this once in the Cloudflare dashboard.
  """

  # Short upload window — the browser kicks off the PUT immediately
  # after fetching the URL, so 5 minutes is generous.
  @put_ttl_seconds 5 * 60

  # Playback URLs need to last for the duration of a typical listening
  # session. 15 minutes covers a song or two; LiveView can refresh on
  # demand if a session runs longer.
  @get_ttl_seconds 15 * 60

  @doc """
  Returns a presigned PUT URL the browser can upload to directly.
  `content_type` is required and bound into the signature so a client
  can't lie about the MIME type after the fact.
  """
  @spec presign_put(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def presign_put(key, content_type) when is_binary(key) and is_binary(content_type) do
    ExAws.S3.presigned_url(config(), :put, bucket(), key,
      expires_in: @put_ttl_seconds,
      query_params: [{"Content-Type", content_type}]
    )
  end

  @doc """
  Returns a presigned GET URL for playback. 15-min TTL — short enough
  that a leaked link expires quickly, long enough for any song.
  """
  @spec presign_get(String.t()) :: {:ok, String.t()} | {:error, term()}
  def presign_get(key) when is_binary(key) do
    ExAws.S3.presigned_url(config(), :get, bucket(), key, expires_in: @get_ttl_seconds)
  end

  @doc """
  HEAD the object after the browser reports upload completion. Returns
  `{:ok, %{size: integer, content_type: String.t()}}` or an error if
  R2 hasn't seen the object (client lied / aborted / something else).
  """
  @spec head(String.t()) :: {:ok, %{size: integer(), content_type: String.t()}} | {:error, term()}
  def head(key) when is_binary(key) do
    case ExAws.S3.head_object(bucket(), key) |> ExAws.request() do
      {:ok, %{headers: headers}} ->
        h =
          for {k, v} <- headers, into: %{}, do: {String.downcase(k), v}

        {:ok,
         %{
           size: parse_int(h["content-length"]),
           content_type: h["content-type"] || "application/octet-stream"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes the object. Used by the orphan sweeper and by the manage
  page when a user deletes a song.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key) when is_binary(key) do
    case ExAws.S3.delete_object(bucket(), key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists keys in the bucket (paginated). Used by the orphan sweeper to
  find R2 objects without a matching `songs.storage_key`.
  """
  @spec list_keys(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_keys(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")

    case ExAws.S3.list_objects(bucket(), prefix: prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        {:ok, Enum.map(contents, & &1.key)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The configured bucket name. Raises if R2_BUCKET is unset — failing
  loud here is better than silently writing into the wrong bucket
  (or worse, the empty-string bucket that S3 may interpret oddly).
  """
  def bucket do
    Application.get_env(:mixwave, :r2_bucket) ||
      raise """
      R2_BUCKET is not configured. Set it in the environment, or in
      .env.local for dev. See `Mixwave.Storage` moduledoc.
      """
  end

  defp config, do: ExAws.Config.new(:s3)

  defp parse_int(nil), do: 0
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(n) when is_integer(n), do: n
end
