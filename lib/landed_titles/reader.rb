# frozen_string_literal: true

module LandedTitles
  class Reader
    class Title
      attr_reader :name, :offset, :cultural_names

      def initialize(name, offset)
        @name = name
        @offset = offset
        @cultural_names = {}
      end
    end

    class CulturalName
      attr_reader :value, :comment, :source

      def initialize(value, comment, source)
        @value = value
        @comment = comment
        @source = source
      end
    end

    TITLE_NAME_REGEXP = /^(?<offset>\s*)(?<title>(?:h|e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
    CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
    NAME_LIST_REGEXP = /(?<!#)(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>[^#]+)(?:\s*#\s*(?<comment>.+))?$/

    attr_reader :name, :file_path

    def initialize(name, file_path)
      @name = name
      @file_path = file_path
      @on_line_read = nil
    end

    def read(&on_title_read)
      raise StandardError, "#{file_path} is not a file" unless File.file?(file_path)

      File.open(file_path, 'r') do |file|
        read_recursive(nil, file, &on_title_read)
      end
    end

    def on_line_read(&block)
      @on_line_read = block
    end

    private

    def read_recursive(title, file, &on_title_read)
      reading_cultural_names = false
      opened_blocks = 1 # title opening block was opened in parent call

      until file.eof?
        line = file.readline

        opened_blocks += 1 if line.include?('{')
        opened_blocks -= 1 if line.include?('}')

        if (match = TITLE_NAME_REGEXP.match(line))
          inner_title = Reader::Title.new(match[:title], match[:offset])
          # Close block as @on_line_break won't get called later
          @on_line_read&.call(line, false)
          read_recursive(inner_title, file, &on_title_read)
          opened_blocks -= 1
          next
        elsif title && opened_blocks < 1
          on_title_read.call(title)
          # Close block as @on_line_break won't get called later
          @on_line_read&.call(line, false)
          break
        elsif reading_cultural_names && (match = NAME_LIST_REGEXP.match(line))
          add_cultural_name(title, match)
        end

        reading_cultural_names = true if CULTURAL_NAMES_REGEXP.match(line)

        @on_line_read&.call(line, reading_cultural_names)

        reading_cultural_names = false if reading_cultural_names && opened_blocks < 2
      end
    end

    def add_cultural_name(title, match)
      cultural_name = match[:cultural_name]
      # Some mod titles files can contain closing bracket on the line
      cultural_name.delete!('}')
      # Some mod titles files can contain several definition per line
      # Likely formatting issue, but needs to be handled
      if cultural_name.include?('name_list_')
        cultural_name, *rest = cultural_name.split(/(?=name_list_)/)

        rest.each do |fragment|
          sub_match = NAME_LIST_REGEXP.match(fragment)
          raise StandardError if sub_match.nil?

          add_cultural_name(title, sub_match)
        end
      end
      title.cultural_names[match[:name_list]] = Reader::CulturalName.new(
        cultural_name.strip, match[:comment], name
      )
    end
  end
end
