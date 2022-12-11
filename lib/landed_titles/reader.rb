module LandedTitles
  class Reader
    TITlE_NAME_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
    CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
    NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>.+)(?:\s*#\s*(?<comment>.+))$/

    attr_reader :name, :file_path

    def initialize(name, file_path)
      @name = name
      @file_path = file_path
    end

    def read(&on_title_read)
      raise StandardError, "#{file_path} is not a file" unless File.file?(file_path)
      File.open(file_path, 'r') do |file|
        read_recursive(nil, file, &on_title_read)
      end
    end

    private

    def read_recursive(title, file, &on_title_read)
      reading_cultural_names = false
      closing_title_regexp = title ? end_of_title_regexp(title) : nil
      closing_cultural_names_regexp = title ? end_of_cultural_names_regexp(title) : nil

      until file.eof?
        line = file.readline

        if (match = TITlE_NAME_REGEXP.match(line))
          inner_title = Title.new(match[:title], match[:offset])
          read_recursive(inner_title, file, &on_title_read)
        elsif title && closing_title_regexp.match?(line)
          on_title_read.call(title)
          break
        elsif CULTURAL_NAMES_REGEXP.match(line)
          reading_cultural_names = true
        elsif reading_cultural_names && (match = NAME_LIST_REGEXP.match(line))
          cultural_name = Title::CulturalName.new(match[:cultural_name].strip, match[:comment])
          title.cultural_names[match[:name_list]]
        elsif reading_cultural_names && closing_cultural_names_regexp.match?(line)
          reading_cultural_names = false
        end
      end
    end

    def end_of_title_regexp(title)
      closing_expression(title.offset)
    end

    def end_of_cultural_names_regexp(title)
      closing_expression(title.offset + "\t")
    end

    def closing_expression(offset)
      Regexp.new("^#{offset}}")
    end
  end
end