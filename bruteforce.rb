# frozen_string_literal: true

TITlE_REGEXP = /^(?<offset>\s*)(?<title>(?:e|k|d|c|b)_[\w\-']+)\s*=\s*\{/

file = ARGV[0]
if file.nil? || !File.file?(file)
  puts "No file found under '#{file}'"
  exit(-1)
end

lines = File.readlines(file)

last_title = nil
titles = {}

lines.each do |line|
  match = TITlE_REGEXP.match line
  next if match.nil?

  title = match[:title]
  last_title = title

  titles[title] = {
    offset: match[:offset],
    cultural_names: {}
  }
end
