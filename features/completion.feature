Feature: Completion
  Shell completion for commands are an important feature of any cli
  As a CLI user
  I want to be able to complete commands and options

  # TODO: Make this not raise an exception and just show the usage instead
  Scenario: Showing exception when no shell is given
    When I run `lc completion`
    Then the output should contain:
      """
      missing keyword: :shell (ArgumentError)
      """

  Scenario: Showing exception when an invalid shell is given
    When I run `lc completion invalid`
    Then the output should contain:
      """
      Unknown shell (ArgumentError)
      """

  Scenario: Outputting the correct completions for bash
    When I run `lc completion bash`
    Then the output should contain:
      """
      # lc completion                                            -*- shell-script -*-
      """
