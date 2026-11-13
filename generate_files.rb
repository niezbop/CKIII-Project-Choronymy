# frozen_string_literal: true

require 'erb'
require 'json'
require 'yaml'
require 'fileutils'
require_relative 'lib/landed_titles'

CONFIGURATION_FILE = './config.yml'

configuration_file = ARGV[0] || CONFIGURATION_FILE
unless File.file?(configuration_file)
  puts "Configuration file #{configuration_file} is missing"
  exit(-1)
end
configuration = YAML.load_file(configuration_file)

#=== STATS SETUP
stats = Hash.new(0)

#=== VERSION PARSING
parsed_versions = {}

launcher_settings_path = configuration['title_files']['base']['vanilla']
                         .sub(/game.*$/,
                              File.join('launcher', 'launcher-settings.json'))
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

#=== LOCALIZATION SETUP
def localization_key(cultural_name)
  "cn_pd_#{cultural_name.title.name}_#{cultural_name.name_list.sub('name_list_', '')}"
end

def get_localization_key(cultural_name, cache)
  if cache.has_key?(cultural_name.value)
    cache[cultural_name.value]
  else
    key = localization_key(cultural_name)
    cache[cultural_name.value] = key
    key
  end
end

#=== CULTURAL NAME AGGREGATION
def generate_output_path(file_config)
  output_file_name = file_config['mods'].map { |_source, path| File.basename(path) }.sort.last
  output_file_path = File.join('target', 'common', 'landed_titles', output_file_name)
  FileUtils.mkdir_p(File.dirname(output_file_path))
  output_file_path
end

def generate_source_ordering(configuration)
  mods = configuration['title_files'].values.first['mods'].keys.reverse
  sources = mods + ['vanilla']

  ordering = "CASE #{LandedTitles::CulturalName.table_name}.source"
  sources.each_with_index do |source, index|
    ordering += " WHEN '#{source}' THEN #{index + 1}"
  end
  ordering += " ELSE #{sources.count + 1} END"
  ordering
end

SOURCE_ORDERING = generate_source_ordering(configuration)

def get_cultural_names(title)
  landed_title = LandedTitles::Title.find_by_name(title.name)

  LandedTitles::CulturalName.where(title: landed_title)
                            .select('cultural_names.*', "MIN(#{SOURCE_ORDERING}) AS source_rank") # Relies on SQLite quirk, wouldn't work in other databases
                            .group(:name_list)
end

localization_key_cache = {}
localization_entries = {}

LandedTitles::Persistence.create_database(persist_to: 'tmp/titles.sqlite')

configuration['title_files'].each_value do |file_config|
  File.open(file_config['vanilla'], 'r') do |vanilla_file|
    reader = LandedTitles::Reader.new('vanilla', vanilla_file)

    output_file_path = generate_output_path(file_config)
    File.open(output_file_path, 'w') do |output_file|
      puts "# WRITING output (#{output_file_path})..."

      # Don't write cultural_names block now
      reader.on_line_read { |line, reading_cultural_names| output_file.write(line) unless reading_cultural_names }
      reader.read do |title|
        # Aggregate all cultural names
        cultural_names = get_cultural_names(title)

        if cultural_names.any?
          # Start cultural_names declaration as it was skipped earlier
          output_file.puts("#{title.offset}\tcultural_names = {")
          cultural_names.each do |cultural_name|
            stats[cultural_name.source] += 1

            localization_key = get_localization_key(cultural_name, localization_key_cache)
            output_file.puts("#{title.offset}\t\t#{cultural_name.name_list} = #{localization_key}")
            localization_entries[localization_key] ||= cultural_name
          end
          output_file.puts(title.offset + "\t" + '}')
        end
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
  localization_entries.sort_by { |k, _| k }.each do |key, cultural_name|
    comment = if cultural_name.comment.nil? or cultural_name.comment.strip.empty?
                cultural_name.source
              else
                [cultural_name.comment.strip, cultural_name.source].join(' - ')
              end

    file.puts(" #{key}:0 \"#{cultural_name.value}\" # #{comment}")
  end
end

%w[french spanish].each do |locale|
  localized_path = output_localize_path.gsub('english', locale)
  FileUtils.mkdir_p(File.dirname(localized_path))
  FileUtils.cp(output_localize_path, localized_path)
  data = File.read(localized_path)
  data = data.sub('l_english:', "l_#{locale}:")
  File.open(localized_path, 'r+') { |file| file.write data }
end

puts '### STATS'
stats.sort_by { |_k, v| v }.each do |k, v|
  puts "• #{k}: #{v} entries"
end

File.write(File.join('target', 'stats.json'), JSON.pretty_generate(stats))

puts '### ABOUT'
template = ERB.new File.read('project_choronymy.about.erb')
File.write('project_choronymy.about.txt', template.result)

puts '===> Bruteforce process completed with success! You can run'
puts "\tcp -r target/* project_choronymy"
puts 'to propagate the changes'
