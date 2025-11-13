# frozen_string_literal: true

module LandedTitles
  class Reader
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
          inner_title = Title.new(match[:title], match[:offset])
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
          title.cultural_names[match[:name_list]] = Title::CulturalName.new(
            match[:cultural_name].strip, match[:comment], name
          )
        end

        reading_cultural_names = true if CULTURAL_NAMES_REGEXP.match(line)

        @on_line_read&.call(line, reading_cultural_names)

        reading_cultural_names = false if reading_cultural_names && opened_blocks < 2
      end
    end
  end
end
