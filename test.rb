# frozen_string_literal: true

require_relative 'lib/clausewitz'

test_file = ARGV[0]
if test_file.nil? || !File.file?(test_file)
  puts "No file found under '#{test_file}'"
  exit(-1)
end

lexer = Clausewitz::Parsing::Lexer.new

lexer.tokenize(File.read(test_file)).each do |token, line, first, last|
  puts "L#{line} #{first}:#{last} #{token.inspect}"
end
