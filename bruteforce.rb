# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require_relative 'lib/landed_titles'

TITLE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/.freeze
CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/.freeze
NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>.+)$/.freeze
LOCALIZATION_KEY_REGEXP = /\s+(?<key>[\w\-]+):\d+\s(?<value>[^#]+)(?:\s*#\s*(?<comment>.+))?$/.freeze

CONFIGURATION_FILE = './config.yml'
BLOCKLIST_FILE = './blocklist.yml'
FIXLIST_FILE = './fixlist.yml'

configuration_file = ARGV[0] || CONFIGURATION_FILE

unless File.file?(configuration_file)
  puts "Configuration file #{configuration_file} is missing"
  exit(-1)
end

titles = {}

configuration = YAML.load_file(configuration_file)

unless File.file?(configuration['title_files']['vanilla'])
  puts "Vanilla title files #{configuration['title_files']['vanilla']} is not a file"
  exit(-1)
end

fallback_cultures = configuration['fallbacks'] || {}

def get_fallbacks(cultural_names, fallback_cultures)
  fallback_cultures.map do |name, fallback_name|
    # Skip fallback if either the fallback culture is missing or the original is already defined
    next nil if cultural_names.keys.include?(name) || !cultural_names.keys.include?(fallback_name)

    [name, cultural_names[fallback_name]]
  end.compact.to_h
end

parsed_versions = {}

# Read versions
launcher_settings_path = configuration['title_files']['vanilla'].sub(/game.*$/,
                                                                     File.join('launcher', 'launcher-settings.json'))
if File.file?(launcher_settings_path)
  puts "Reading vanilla version from #{launcher_settings_path}..."
  parsed_versions[:vanilla] = JSON.parse(File.read(launcher_settings_path))['rawVersion']
else
  puts "No file at #{launcher_settings_path}, skipping vanilla version parsing..."
end

configuration['title_files']['mods'].each do |source, file|
  descriptor_path = file.sub(/common.*/, 'descriptor.mod')
  puts "Reading #{source} version from #{descriptor_path}..."
  version_line = `grep "version=" #{descriptor_path} | grep -v supported_version`
  parsed_versions[source] = version_line.sub(/version="([^\s]+)"\s*$/, '\1')
end

FileUtils.mkdir_p('target')
File.write(File.join('target', 'parsed_versions.json'), JSON.pretty_generate(parsed_versions))

blocklist = if File.file?(BLOCKLIST_FILE)
              puts "Reading blocklist at #{BLOCKLIST_FILE}..."
              YAML.load_file(BLOCKLIST_FILE)
            else
              {}
            end

fixlist = if File.file?(FIXLIST_FILE)
            puts "Reading fixlist at #{FIXLIST_FILE}..."
            YAML.load_file(FIXLIST_FILE)
          else
            {}
          end

# Read mod titles
configuration['title_files']['mods'].each do |source, file|
  reader = LandedTitles::Reader.new(source, file)

  puts "# READING #{source} (#{file})..."
  source_titles = {}
  reader.read do |title|
    (blocklist.dig(source, title.name) || []).each do |name_list_to_block|
      if title.cultural_names.delete(name_list_to_block)
        puts "\tBlocking #{name_list_to_block} for #{title.name} from #{source}"
      end
    end

    fixlist.dig(source, 'culture_names')&.each do |name_list_to_fix, name_list_fixing|
      if value = title.cultural_names.delete(name_list_to_fix)
        puts "\tReplacing #{name_list_to_fix} with #{name_list_fixing} for #{title.name} from #{source}"
        title.cultural_names[name_list_fixing] = value
      end
    end

    source_titles[title.name] = title
  end

  titles[source] = source_titles
  puts "\tFound #{source_titles.keys.count} titles for #{source}"
  puts "\t#{source_titles.reject { |_k, v| v.cultural_names.empty? }.count} of them have cultural names"
end

output_file_name = configuration['title_files']['mods'].map { |_source, path| File.basename(path) }.sort.last
output_file_path = File.join('target', 'common', 'landed_titles', output_file_name)
FileUtils.mkdir_p(File.dirname(output_file_path))

stats = Hash.new(0)

localizations = configuration['localization_files'].transform_values do |file|
  raise StandardError, "#{file} is not a file" unless File.file?(file)

  puts "# READING LOCALIZATION AT #{file}"

  entries = {}

  File.readlines(file).each do |line|
    if (match = LOCALIZATION_KEY_REGEXP.match(line))
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

def get_localization_value(localizations, source, value)
  output = localizations.dig(source, value) ||
           localizations.dig('vanilla', value) ||
           value

  puts output.value, output.source if output.is_a? LandedTitles::Title::CulturalName
  return output unless output.start_with?('cn_') && output != value

  get_localization_value(localizations, output, source)
end

def localization_key(title, name_list)
  "cn_pd_#{title.name}_#{name_list.sub('name_list_', '')}"
end

localization_key_sources = {}
to_localize = {}

File.open(configuration['title_files']['vanilla'], 'r') do |vanilla_file|
  reader = LandedTitles::Reader.new('vanilla', vanilla_file)
  File.open(output_file_path, 'w') do |output_file|
    puts "# WRITING output (#{output_file_path})..."

    # Don't write cultural_names block now
    reader.on_line_read { |line, reading_cultural_names| output_file.write(line) unless reading_cultural_names }
    reader.read do |title|
      # Aggregate all cultural names
      cultural_names = # Inject fallback names at the top of the possibilities so that they're later merged over by proper ones
        configuration['title_files']['mods']
        .keys
        .map { |source| titles.dig(source, title.name) } # Get title from source
        .compact # Reject mods that don't have the title declared
        .map(&:cultural_names) # Get the list of cultural names
        .tap do |names|
          names.reverse.map do |n|
            get_fallbacks(n, fallback_cultures)
          end.each { |fn| names.unshift(fn) }
        end.reduce(title.cultural_names) { |aggregate, names| aggregate.merge(names) }
        .sort_by { |k, _v| k }

      if cultural_names.any?
        # Start cultural_names declaration as it was skipped earlier
        output_file.puts("#{title.offset}\tcultural_names = {")
        cultural_names.each do |name_list, cultural_name|
          # Simplify localization
          localized_value = clean_value(get_localization_value(localizations, cultural_name.source,
                                                               cultural_name.value))
          localization_key = if localization_key_sources.has_key?(localized_value)
                               localization_key_sources[localized_value]
                             else
                               key = localization_key(title, name_list)
                               localization_key_sources[localized_value] = key
                             end

          output_file.puts("#{title.offset}\t\t#{name_list} = #{localization_key}")
          to_localize[localization_key] ||= [cultural_name, localized_value]
          stats[cultural_name.source] += 1
        end
        output_file.puts(title.offset + "\t" + '}')
      end
    end
  end
end

puts '### LOCALIZATION'

output_localize_path = File.join('target', 'localization', 'english',
                                 'project_choronymy_titles_cultural_names_l_english.yml')
FileUtils.mkdir_p(File.dirname(output_localize_path))

File.open(output_localize_path, 'w') do |file|
  puts "# WRITING LOCALIZATION AT #{file.path}"
  file.write("\uFEFF") # Set BOM
  file.puts('l_english:')
  to_localize.sort_by { |k, _v| k }.each do |key, (cultural_name, value)|
    comment = if cultural_name.comment.nil? or cultural_name.comment.strip.empty?
                cultural_name.source
              else
                [cultural_name.comment.strip, cultural_name.source].join(' - ')
              end

    file.puts(" #{key}:0 #{clean_value(value)} # #{comment}")
  end
end

puts '### STATS'
stats.sort_by { |_k, v| v }.each do |k, v|
  puts "• #{k}: #{v} entries"
end

File.write(File.join('target', 'stats.json'), JSON.pretty_generate(stats))

puts '===> Bruteforce process completed with success! You can run'
puts "\tcp -r target/* project_choronymy"
puts 'to propagate the changes'
