# frozen_string_literal: true

require_relative 'tokens'

module Clausewitz
  module Parsing
    class Lexer
      include Clausewitz::Parsing::Tokens

      attr_reader :token_builder,
        :token_first_column,
        :token_last_column,
        :tokens

      def initialize
        @token_builder = @token_first_column = @token_last_column = nil
        @tokens = []
      end

      def tokenize(string)
        tokens = []

        # TODO: Handle string declarations
        string.split("\n").each_with_index do |line, line_number|
          token_builder = token_start = nil
          # read_string = false
          line.chars.each_with_index do |character, char_number|
            break if character == '#'
            if character.strip.empty?
              finalize_token(token_builder, line_number, token_start, char_number, tokens)
              next
            end
            if token_start.nil?
              token_start = char_number
            end

            if TOKENIZABLE_CHARACTERS.key?(character)
              finalize_token(token_builder, line_number, token_start, char_number, tokens)
              finalize_token(character, line_number, char_number, char_number + 1, tokens)
            else
              token_builder ||= ""
              token_builder += character
            end
          end

          finalize_token(token_builder, line_number, token_start, line.chars.count, tokens)
          finalize_token("\n", line_number, line.chars.count, line.chars.count + 1, tokens)
        end

        tokens
      end

      private

      attr_writer :token_builder,
        :token_first_column,
        :token_last_column,
        :tokens

      def finalize_token(token_builder, line_number, token_start, char_number, tokens)
        return if token_start.nil?
        finalized_token = if TOKENIZABLE_CHARACTERS.key?(token_builder)
          TOKENIZABLE_CHARACTERS[token_builder]
        else
          token_builder
        end

        tokens << [finalized_token, line_number, token_start, char_number]
        token_builder = token_start = nil
      end
    end
  end
end
