# frozen_string_literal: true
require 'json'
require 'yaml'
require 'fileutils'
require_relative 'lib/landed_titles'

TITlE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>.+)$/
LOCALIZATION_KEY_REGEXP = /\s+(?<key>[\w\-]+):0\s(?<value>[^#]+)(?:\s*#\s*(?<comment>.+))?$/

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
  reader = LandedTitles::Reader.new(source, file)

  puts "# READING #{source} (#{file})..."
  source_titles = {}
  reader.read do |title|
    source_titles[title.name] = title
  end

  titles[source] = source_titles
  puts "\tFound #{source_titles.keys.count} titles for #{source}"
  puts "\t#{source_titles.reject {|_k,v| v.cultural_names.empty? }.count} of them have cultural names"
end

output_file_path = File.join('target', File.basename(configuration['title_files']['vanilla']))
FileUtils.mkdir_p(File.dirname(output_file_path))

stats = Hash.new(0)

def localization_key(title, name_list)
  "cn_pd_#{title.name}_#{name_list.sub(/name_list_/, "")}"
end

to_localize = {}

File.open(configuration['title_files']['vanilla'], 'r') do |vanilla_file|
  reader = LandedTitles::Reader.new('vanilla', vanilla_file)
  File.open(output_file_path, 'w') do |output_file|
    puts "# WRITING output (#{output_file_path})..."

    # Don't write cultural_names block now
    reader.on_line_read { |line, reading_cultural_names| output_file.write(line) unless reading_cultural_names }
    reader.read do |title|
      # Aggregate all cultural names
      cultural_names = configuration['title_files']['mods']
        .keys
        .map { |source| titles.dig(source, title.name) }
        .compact
        .map(&:cultural_names)
        .reduce(title.cultural_names) { |aggregate, names| aggregate.merge(names) }
        .sort_by { |k,_v| k }

      if cultural_names.any?
        # Start cultural_names declaration as it was skipped earlier
        output_file.puts("#{title.offset}\tcultural_names = {")
        cultural_names.each do |name_list, cultural_name|
          localization_key = localization_key(title, name_list)
          output_file.puts("#{title.offset}\t\t#{name_list} = #{localization_key}")
          to_localize[localization_key] = cultural_name
          stats[cultural_name.source] += 1
        end
        output_file.puts(title.offset + "\t" + "}")
      end
    end
  end
end

puts '### LOCALIZATION'

output_localize_path = File.join('target', 'localization', 'english', 'titles_cultural_names_l_english.yml')
FileUtils.mkdir_p(File.dirname(output_localize_path))

localizations = configuration['localization_files'].transform_values do |file|
  raise StandardError, "#{file} is not a file" unless File.file?(file)
  puts "# READING LOCALIZATION AT #{file}"

  entries = {}

  File.readlines(file).each do |line|
    if(match = LOCALIZATION_KEY_REGEXP.match(line))
      entries[match[:key]] = match[:value]
    end
  end

  entries
end

def clean_value(value)
  value_clean = value.strip
  value_clean = "\"#{value_clean}\"" unless /"/.match(value_clean)
  value_clean
end

File.open(output_localize_path, 'w') do |file|
  puts "# WRITING LOCALIZATION AT #{file.path}"
  file.write("\uFEFF") # Set BOM
  file.puts('l_english:')
  to_localize.sort_by { |k,_v| k }.each do |key, cultural_name|
    value = localizations.dig(cultural_name.source, cultural_name.value) ||
      localizations.dig('vanilla', cultural_name.value) ||
      cultural_name.value
    comment = if cultural_name.comment.nil? or cultural_name.comment.strip.empty?
      cultural_name.source
    else
      [cultural_name.comment.strip, cultural_name.source].join(' - ')
    end

    file.puts(" #{key}:0 #{clean_value(value)} # #{comment}")
  end
end

puts "### STATS"
stats.sort_by {|_k,v| v}.each do |k,v|
  puts "• #{k}: #{v} entries"
end