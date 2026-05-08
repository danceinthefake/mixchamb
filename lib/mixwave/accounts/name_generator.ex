defmodule Mixwave.Accounts.NameGenerator do
  @moduledoc """
  Generates anonymous-user display names in the form
  `<javanese-adjective>-<javanese-noun>-<NN>`, e.g. `ayu-merak-42`,
  `wani-macan-17`.

  30 adjectives × 30 nouns × 100 numbers = 90 000 unique names. Two-
  digit suffix lets the same adjective+noun pair map to many users
  without collision in practice; if it does collide on insert, the
  caller retries.

  """

  @adjectives ~w(
    ayu bagus pinter wani alus sabar gagah prigel gemati sumringah
    temen jujur semanak prasaja mapan mantep legawa tlaten gemi
    nastiti sigap lega seneng tegep resik trampil anteng wasis
    padhang guyub
  )

  @nouns ~w(
    macan merak garuda gajah kupu menjangan kidang kucing jaran
    kembang mawar melati pari jati bambu gunung kali segara mega
    lintang candra surya angin gelombang esuk wengi gamelan wayang
    batik topeng
  )

  @doc """
  Returns a random `<adj>-<noun>-<NN>` name. NN is zero-padded to 2
  digits so all names sort to the same width.
  """
  def generate do
    adj = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    num = :rand.uniform(100) - 1
    "#{adj}-#{noun}-#{num |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
