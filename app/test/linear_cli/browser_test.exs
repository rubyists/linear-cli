defmodule LinearCli.BrowserTest do
  use ExUnit.Case, async: true

  alias LinearCli.Browser

  describe "open_url/2" do
    test "calls the injected opener with the URL" do
      test_pid = self()

      assert :ok =
               Browser.open_url("https://linear.app/the-rubyists/issue/EXT-20",
                 opener: fn url ->
                   send(test_pid, {:opened, url})
                   :ok
                 end
               )

      assert_received {:opened, "https://linear.app/the-rubyists/issue/EXT-20"}
    end

    test "returns the opener's error result unchanged" do
      assert {:error, :fake_error} =
               Browser.open_url("https://example.com",
                 opener: fn _url -> {:error, :fake_error} end
               )
    end
  end
end
