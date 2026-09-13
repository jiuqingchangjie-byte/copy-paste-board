#!/usr/bin/env ruby
# Check every literal localization key in production sources against the compiled catalog.
require 'json'
root = File.expand_path('..', __dir__)
catalog = File.read(File.join(root, 'Sources/ClipboardCore/Localization/Translations.swift'))
keys = catalog.scan(/^        ("(?:\\.|[^"\\])*"): \[/).flatten.map { |s| JSON.parse(s) }
errors = []
Dir[File.join(root, 'Sources/**/*.swift')].each do |file|
  next if file.end_with?('/Translations.swift')
  File.read(file).scan(/L10n\.tr\(("(?:\\.|[^"\\])*")/).flatten.each do |literal|
    key = JSON.parse(literal)
    errors << "#{file}: missing #{key}" unless keys.include?(key)
  end
end
abort errors.join("\n") unless errors.empty?
puts "PASS: #{keys.length} catalog entries; every literal interface key has translations."
