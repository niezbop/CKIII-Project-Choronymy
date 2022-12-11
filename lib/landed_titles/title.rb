module LandedTitles
  class Title
    attr_reader :name, :offset, :cultural_names

    def initialize(name, offset)
      @name = name
      @offset = offset
      @cultural_names = {}
    end

    class CulturalName
      attr_reader :value, :comment

      def initialize(value, comment)
        @value = value
        @comment = comment
      end
    end
  end
end