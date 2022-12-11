# frozen_string_literal: true
require 'json'
require 'yaml'
require 'fileutils'
require_relative 'lib/landed_titles'

TITlE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>.+)$/

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

localization = {}

File.open(configuration['title_files']['vanilla'], 'r') do |vanilla_file|
  reader = LandedTitles::Reader.new(:vanilla, vanilla_file)
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
        output_file.puts(title.offset + "\t" + "cultural_names = {")
        cultural_names.each do |name_list, cultural_name|
          localization_key = localization_key(title, name_list)
          output_file.puts("#{title.offset}\t\t#{name_list} = #{localization_key}")
          localization[localization_key] = cultural_name.value
          stats[cultural_name.source] += 1
        end
        output_file.puts(title.offset + "\t" + "}")
      end
    end
  end
end

puts "# STATS"
stats.sort_by {|_k,v| v}.each do |k,v|
  puts "• #{k}: #{v} entries"
end