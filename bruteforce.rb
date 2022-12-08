# frozen_string_literal: true
require 'json'

TITlE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/
CULTURAL_NAMES_REGEXP = /^(?<offset>\s*)cultural_names/
NAME_LIST_REGEXP = /(?<name_list>name_list_\w+)\s*=\s*(?<cultural_name>[\w\-]+)/

file = ARGV[0]
if file.nil? || !File.file?(file)
  puts "No file found under '#{file}'"
  exit(-1)
end

lines = File.readlines(file)

last_title = nil
titles = {}

lines.each do |line|
  if (match = TITlE_REGEXP.match line)
    title = match[:title]
    last_title = title

    titles[title] = { offset: match[:offset] }
  elsif (match = CULTURAL_NAMES_REGEXP.match line)
    titles[last_title][:cultural_names] = {}
  elsif (match = NAME_LIST_REGEXP.match line)
    titles[last_title][:cultural_names][match[:name_list]] = match[:cultural_name]
  end
end

File.open('output.json', 'w') {|f| f.write JSON.pretty_generate(titles) }