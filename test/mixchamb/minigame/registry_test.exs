defmodule Mixchamb.MiniGame.RegistryTest do
  use ExUnit.Case, async: true

  alias Mixchamb.MiniGame.Registry

  test "keys, default, valid?, module, label" do
    assert Registry.keys() == ~w(gartic_phone pictionary two_truths)
    assert Registry.default() == "pictionary"
    assert Registry.valid?("two_truths")
    refute Registry.valid?("nope")
    refute Registry.valid?(nil)
    assert Registry.module("gartic_phone") == Mixchamb.MiniGame.GarticPhone
    assert Registry.module("nope") == Mixchamb.MiniGame.Pictionary
    assert Registry.label("pictionary") == "Pictionary"
    assert Registry.label("gartic_phone") == "Gartic Phone"
    assert Registry.label("two_truths") == "Two Truths & a Lie"
    assert Registry.label("custom") == "Custom"
  end
end
