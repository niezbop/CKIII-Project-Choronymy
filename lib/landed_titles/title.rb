module LandedTitles
  class Title
    attr_reader :name, :offset, :cultural_names

    def initialize(name, offset)
      @name = name
      @offset = offset
      @cultural_names = {}
    end

    class CulturalName
      attr_reader :value, :comment, :source

      def initialize(value, comment, source)
        @value = value
        @comment = comment
        @source = source
      end
    end
  end
end