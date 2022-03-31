# frozen_string_literal: true

module Clausewitz
  module Parsing
    module Tokens
      LINE_BREAK = :line_break
      WHITESPACE = :whitespace

      # Blocks
      BLOCK_OPEN = :block_open
      BLOCK_CLOSE = :block_close

      # Booleans
      YES = :yes
      NO = :no

      # Operators
      EQUALS = :equals
      PLUS = :plus
      MINUS = :minus

      TOKENIZABLE_CHARACTERS = {
        "\n" => LINE_BREAK,
        '{' => BLOCK_OPEN,
        '}' => BLOCK_CLOSE,
        'yes' => YES,
        'no' => NO,
        '=' => EQUALS,
        '+' => PLUS,
        '-' => MINUS
      }.freeze
    end
  end
end
