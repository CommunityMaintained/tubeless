defmodule Pinchflat.Utils.StringUtils do
  @moduledoc """
  Utility methods for working with strings
  """

  @doc """
  Converts a string to kebab-case (ie: `hello world` -> `hello-world`)

  Returns binary()
  """
  def to_kebab_case(string) do
    string
    |> String.replace(~r/[\s_]/, "-")
    |> String.downcase()
  end

  @doc """
  Converts a string to a URL- and filesystem-safe slug (ie: `The Verge!` ->
  `the-verge`). Collapses runs of non-alphanumeric characters to a single dash
  and trims leading/trailing dashes. Returns `""` when the input has no usable
  characters (eg: a fully non-latin name) so the caller can supply a fallback.

  Returns binary()
  """
  def to_slug(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  @doc """
  Returns a random string of the given length. Base 16 encoded, lower case.

  Returns binary()
  """
  def random_string(length \\ 32) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16(case: :lower)
    |> String.slice(0..(length - 1))
  end

  @doc """
  Wraps a string in double braces. Useful as a UI helper now that
  LiveView 1.0.0 allows `{}` for interpolation so now we can't use braces
  directly in the view.

  Returns binary()
  """
  def double_brace(string) do
    "{{ #{string} }}"
  end

  @doc """
  Wraps a string in quotes if it's not already a string. Useful for working with
  error messages whose types can vary.

  Returns binary()
  """
  def wrap_string(message) when is_binary(message), do: message
  def wrap_string(message), do: "#{inspect(message)}"
end
