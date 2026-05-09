defmodule Mixwave.Accounts.NameGenerator do
  @moduledoc """
  Generates anonymous-user display names in the form
  `<funny-javanese-adjective>-<funny-javanese-noun>-<NN>`, e.g.
  `gendheng-tempe-42`, `mendhem-bakso-17`, `ngantuk-monyet-08`.

  Adjectives lean playful / mildly absurd Javanese descriptors —
  drunk, dazed, slovenly, dorky, sleepy, naughty. Nouns are
  Javanese food, animals, and body parts that read as funny
  whether you speak Javanese or not. Net effect: every login gets
  a name that sounds like a comedy-skit character who showed up
  to jam.

  30 adjectives × 30 nouns × 100 numbers = 90 000 unique names.
  Two-digit suffix lets the same adjective+noun pair map to many
  users without collision in practice; if it does collide on
  insert, the caller retries.

  """

  @adjectives ~w(
    gendheng edan kemproh cubluk cengeng culun mendhem klimis
    kemayu kemlinthi mblenger bantet kuru lemu ndlahom ndlosor
    ndableg kemladhean bedhes cilik gembleng alon nakal bandel
    slengeran lelet lemes ngantuk keseseg kringeten
  )

  @nouns ~w(
    tempe tahu bakso cendol klepon getuk krupuk peyek bakwan
    lemper sambal jagung timun terong jengkol pisang udel
    jenggot bekicot yuyu lutung monyet celeng kebo belut kodok
    tikus cacing kambing ayam
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
