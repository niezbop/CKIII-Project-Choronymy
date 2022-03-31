# frozen_string_literal: true

module Clausewitz
  module Parsing
    module SyntaxTree
      class Node
        attr_accessor :children,
                      :first_line_number,
                      :first_column,
                      :last_line_number,
                      :last_column

        def initialize(children: [], first_line_number: nil, first_column: nil, last_line_number: nil, last_column: nil)
          @children = children
          @first_line_number = first_line_number
          @first_column = first_column
          @last_line_number = last_line_number
          @last_column = last_column
        end

        def leaf?
          children.none?
        end
      end
    end
  end
end
