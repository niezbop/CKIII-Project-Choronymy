# frozen_string_literal: true

require_relative 'tokens'

module Clausewitz
  module Parsing
    class Lexer
      include Clausewitz::Parsing::Tokens

      def tokenize(string)
        tokens = []

        # TODO: Handle string declarations
        string.split("\n").each do |line|
          line.split(/\s/).each do |substring|
            break if substring.start_with?('#') # Ignore all tokens on the line, they're part of a comment
            next if substring.empty?

            tokens << to_token(substring)
          end

          tokens << LINE_BREAK
        end

        tokens
      end

      private

      def to_token(string)
        if TOKENIZABLE_CHARACTERS.key?(string)
          TOKENIZABLE_CHARACTERS[string]
        else
          string # Consider it a random string
        end
      end
    end
  end
end
