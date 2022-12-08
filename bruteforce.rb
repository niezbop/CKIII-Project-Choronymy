# frozen_string_literal: true
require 'json'
require 'yaml'
require 'fileutils'

TITlE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>[\w\-]+)/

CONFIGURATION_FILE = './config.yml'

unless File.file?(CONFIGURATION_FILE)
  puts "Configuration file #{CONFIGURATION_FILE} is missing"
  exit -1
end

titles = {}

configuration = YAML.load(File.read(CONFIGURATION_FILE))

unless File.file?(configuration['title_files']['vanilla'])
  puts "Vanilla title files #{configuration['title_files']['vanilla']} is not a file"
  exit -1
end

# Read mod titles
configuration['title_files']['mods'].each do |source, file|
  puts "# READING #{source} (#{file})..."
  unless File.file?(file)
    puts "#{file} is not a file"
    next
  end

  lines = File.readlines(file)

  source_titles = {}
  last_title = nil

  lines.each_with_index do |line, index|
    if (match = TITlE_REGEXP.match line)
      title = match[:title]
      last_title = title

      source_titles[title] = { offset: match[:offset], cultural_names: {} }
    elsif (match = NAME_LIST_REGEXP.match line)
      source_titles[last_title][:cultural_names][match[:name_list]] = match[:cultural_name]
    end
  rescue => e
    puts "[#{source}][#{last_title}] Failed to parse line #{index}:"
    puts line
    raise e
  end

  titles[source] = source_titles
end

output_file = File.join(
  'target',
  configuration['title_files']['mods'].values.map {|k| File.basename(k) }.sort.last || File.basename(configuration['title_files']['vanilla']))
FileUtils.mkdir_p(File.dirname(output_file))

File.open(configuration['title_files']['vanilla'], 'r') do |vanilla_file|
  File.open(output_file, 'w') do |output_file|
    last_title = nil
    title_offset = ""
    has_cultural_names = false
    current_names = {}

    until vanilla_file.eof?
      line = vanilla_file.readline

      if (match = TITlE_REGEXP.match line)
        # Start a new title declaration
        last_title = match[:title]
        title_offset = match[:offset]
        has_cultural_names = false
        current_names = {}

        output_file.write(line)
      elsif (match = CULTURAL_NAMES_REGEXP.match line)
        # Track cultural_names
        has_cultural_names = true
        current_names = {}
      elsif (match = NAME_LIST_REGEXP.match line)
        current_names[match[:name_list]] = match[:cultural_name]
      elsif Regexp.new("^#{title_offset}}").match(line)
        # Finish the current title declaration
        cultural_names = configuration['title_files']['mods']
          .keys
          .map {|source| titles.dig(source, last_title, :cultural_names) }
          .compact # Remove sources which do not have cultural_names for this title
          .reduce(current_names) {|aggregate, names| aggregate.merge(names) }
          .sort_by { |k,_v| k }

        if cultural_names.any?
          # Start cultural_names declaration (wasn't written earlier)
          output_file.puts(title_offset + "\t" + "cultural_names = {")
          cultural_names.each do |k,v|
            output_file.puts(title_offset + "\t" + "\t" + "#{k} = #{v}")
          end
          output_file.puts(title_offset + "\t" + "}")
        end

        # Properly close title
        output_file.write(line)
      else
        output_file.write(line)
      end
    end
  end
end