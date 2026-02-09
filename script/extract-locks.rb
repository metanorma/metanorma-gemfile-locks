#!/usr/bin/env ruby
# frozen_string_literal: true

##
# CLI to extract Gemfile and Gemfile.lock from metanorma/metanorma Docker images

require_relative "../lib/metanorma_gemfile_locks"
require "optparse"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: extract-locks.rb [options]"

  opts.on("-vVERSION", "--version=VERSION", "Extract specific version") do |v|
    options[:version] = v
  end

  opts.on("-a", "--all", "Extract all available versions") do
    options[:all] = true
  end

  opts.on("-l", "--list", "List available versions") do
    options[:list] = true
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

extractor = MetanormaGemfileLocks::Extractor.new

if options[:list]
  versions = extractor.fetch_docker_hub_versions
  puts "Available versions:"
  versions.each { |v| puts "  #{v}" }
elsif options[:version]
  extractor.extract_version(options[:version])
elsif options[:all]
  extractor.extract_all
else
  puts "Use --help for usage information"
  exit 1
end
