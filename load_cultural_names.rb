# frozen_string_literal: true

require 'erb'
require 'json'
require 'yaml'
require 'fileutils'
require_relative 'lib/landed_titles'

LOCALIZATION_KEY_REGEXP = /\s*(?<key>[^:]+):\d*\s(?<value>[^#]+)(?:\s*#\s*(?<comment>.+))?$/

CONFIGURATION_FILE = './config.yml'
BLOCKLIST_FILE = './blocklist.yml'
FIXLIST_FILE = './fixlist.yml'

configuration_file = ARGV[0] || CONFIGURATION_FILE

unless File.file?(configuration_file)
  puts "Configuration file #{configuration_file} is missing"
  exit(-1)
end

configuration = YAML.load_file(configuration_file)

configuration['title_files'].map { |_, h| h['vanilla'] }.each do |vanilla_file|
  unless File.file?(vanilla_file)
    puts "Vanilla title files #{vanilla_file} is not a file"
    exit(-1)
  end
end

parsed_versions = {}

# Read versions
launcher_settings_path = configuration['title_files']['base']['vanilla'].sub(/game.*$/,
                                                                             File.join('launcher',
                                                                                       'launcher-settings.json'))
if File.file?(launcher_settings_path)
  puts "Reading vanilla version from #{launcher_settings_path}..."
  parsed_versions[:vanilla] = JSON.parse(File.read(launcher_settings_path))['rawVersion']
else
  puts "No file at #{launcher_settings_path}, skipping vanilla version parsing..."
end

configuration['title_files'].values.first['mods'].each do |source, file|
  descriptor_path = file.sub(/common.*/, 'descriptor.mod')
  puts "Reading #{source} version from #{descriptor_path}..."
  version_line = `grep "version=" #{descriptor_path} | grep -v supported_version`
  parsed_versions[source] = version_line.sub(/version="([^\s]+)"\s*$/, '\1')
end

FileUtils.mkdir_p('target')
File.write(File.join('target', 'parsed_versions.json'), JSON.pretty_generate(parsed_versions))

BLOCKLIST = if File.file?(BLOCKLIST_FILE)
              puts "Reading blocklist at #{BLOCKLIST_FILE}..."
              YAML.load_file(BLOCKLIST_FILE)
            else
              {}
            end

FIXLIST = if File.file?(FIXLIST_FILE)
            puts "Reading fixlist at #{FIXLIST_FILE}..."
            YAML.load_file(FIXLIST_FILE)
          else
            {}
          end

#=== LOCALIZATION LOADING
LOCALIZATIONS = configuration['localization_files'].transform_values do |files|
  entries = {}
  files = [files] unless files.is_a?(Array)
  files.each do |file|
    raise StandardError, "#{file} is not a file" unless File.file?(file)

    puts "# READING LOCALIZATION AT #{file}"

    File.readlines(file).each do |line|
      if (match = LOCALIZATION_KEY_REGEXP.match(line))
        entries[match[:key]] = match[:value]
      end
    end
  end

  entries
end

#=== FILES READING
def get_localization_value(localizations, source, value)
  output = localizations.dig(source, value) ||
           localizations.dig('vanilla', value) ||
           value

  return output unless output.start_with?('cn_') && output != value

  get_localization_value(localizations, output, source)
end

def sanitize_cultural_name(source, value)
  localized_value = get_localization_value(LOCALIZATIONS, source, value)
  localized_value.delete('"').strip
end

def persist_title(title)
  landed_title = LandedTitles::Title.find_or_create_by!(name: title.name)
  title.cultural_names.each do |name_list, name|
    landed_title.cultural_names.find_or_create_by!(
      name_list:,
      value: sanitize_cultural_name(name.source, name.value),
      source: name.source
    )
  end
end

def read_source_file(source, file)
  reader = LandedTitles::Reader.new(source, file)

  puts "# READING #{source} (#{file})..."
  reader.read do |title|
    (BLOCKLIST.dig(source, title.name) || []).each do |name_list_to_block|
      if title.cultural_names.delete(name_list_to_block)
        puts "\tBlocking #{name_list_to_block} for #{title.name} from #{source}"
      end
    end

    FIXLIST.dig(source, 'culture_names')&.each do |name_list_to_fix, name_list_fixing|
      if value = title.cultural_names.delete(name_list_to_fix)
        puts "\tReplacing #{name_list_to_fix} with #{name_list_fixing} for #{title.name} from #{source}"
        title.cultural_names[name_list_fixing] = value
      end
    end

    persist_title(title)
  end
end

LandedTitles::Persistence.setup(persist_to: 'tmp/titles.sqlite')

# Read mod titles
configuration['title_files'].each do |file_name, file_config|
  puts "# READING #{file_name} entries"
  file_config['mods'].each do |source, file|
    read_source_file(source, file)
  end
end
