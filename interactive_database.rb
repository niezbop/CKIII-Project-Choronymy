# frozen_string_literal: true

require 'irb'
require_relative 'lib/landed_titles'

DEFAULT_PATH = 'tmp/titles.sqlite'
path = DEFAULT_PATH

unless File.file?(path)
  puts "No title database found at #{path}"
  exit(-1)
end

LandedTitles::Persistence.create_database(persist_to: path)
IRB.start
