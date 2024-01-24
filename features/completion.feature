Feature: Completion
  Shell completion for commands are an important feature of any cli
  As a CLI user
  I want to be able to complete commands and options

  Scenario: Showing help when no shell argument is given
    When I run `lc completion`
    Then the output should contain:
      """
      Something
      """
