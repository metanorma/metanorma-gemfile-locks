#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Extract Gemfile and Gemfile.lock from metanorma/metanorma Docker images
#
# This script pulls Docker images from Docker Hub for each version of
# metanorma/metanorma, extracts the Gemfile and Gemfile.lock files,
# and organizes them into versioned directories.

require "fileutils"
require "json"
require "open-uri"
require "net/http"

module MetanormaGemfileLocks
  DOCKER_IMAGE = "metanorma/metanorma".freeze
  VERSIONS_DIR = File.join(__dir__, "..", "v").freeze

  class Extractor
    attr_reader :versions

    def initialize
      @versions = []
    end

    # Fetch all version tags from Docker Hub
    def fetch_docker_hub_versions
      uri = URI("https://registry.hub.docker.com/v2/repositories/#{DOCKER_IMAGE}/tags?page_size=100")
      versions = []

      loop do
        data = JSON.parse(URI.open(uri).read)
        data["results"].each do |result|
          name = result["name"]
          versions << name if name =~ /^\d+\.\d+\.\d+$/
        end

        break unless data["next"]
        uri = URI(data["next"])
      end

      # Sort versions semantically
      versions.sort_by { |v| v.split(".").map(&:to_i) }
    end

    # Pull a Docker image for a specific version
    def pull_docker_image(version)
      puts "Pulling #{DOCKER_IMAGE}:#{version}..."
      system("docker", "pull", "#{DOCKER_IMAGE}:#{version}")
    end

    # Extract Gemfile and Gemfile.lock from a Docker container
    def extract_from_container(version)
      version_dir = File.join(File.dirname(VERSIONS_DIR), "v#{version}")
      FileUtils.mkdir_p(version_dir)

      # Create extraction script that will run inside the container
      # Search in all possible locations where Gemfile might be:
      # - /metanorma/ (older versions)
      # - /setup/ (newer versions)
      # - / (even older versions)
      # - /root/ (some intermediate versions)
      extract_script = <<~SCRIPT
        #!/bin/sh
        # Find Gemfile location - search in order of likelihood
        for path in /metanorma/Gemfile /setup/Gemfile /Gemfile /root/Gemfile; do
          if [ -f "$path" ]; then
            gemfile_dir=$(dirname "$path")
            echo "GEMFILE_DIR=$gemfile_dir"
            cat "$path"
            echo "===GEMFILE.EOF==="
            cat "$gemfile_dir/Gemfile.lock"
            exit 0
          fi
        done
        echo "ERROR: No Gemfile found"
        echo "Searched: /metanorma/Gemfile /setup/Gemfile /Gemfile /root/Gemfile"
        exit 1
      SCRIPT

      # Run container with the extraction script
      # Override ENTRYPOINT to run our script instead of the default metanorma command
      cmd = <<~CMD
        docker run --rm --entrypoint sh #{DOCKER_IMAGE}:#{version} -c '#{extract_script}'
      CMD

      output = `#{cmd}`
      status = $?.exitstatus

      if status != 0 || output.include?("ERROR: No Gemfile found")
        raise "Failed to extract Gemfile from version #{version}:\n#{output}"
      end

      # Parse output to extract Gemfile and Gemfile.lock
      parts = output.split("===GEMFILE.EOF===")
      if parts.size < 2
        raise "Failed to parse Gemfile output for version #{version}"
      end

      gemfile_content = parts[0].sub(/GEMFILE_DIR=.+\n/, "")
      gemfile_lock_content = parts[1]

      # Write files
      File.write(File.join(version_dir, "Gemfile"), gemfile_content.strip + "\n")
      File.write(File.join(version_dir, "Gemfile.lock"), gemfile_lock_content.strip + "\n")

      gemfile_dir = output[/GEMFILE_DIR=(.+)/, 1]
      puts "  Extracted to v#{version}/ (from #{gemfile_dir})"
    end

    # Extract all versions
    def extract_all
      @versions = fetch_docker_hub_versions
      puts "Found #{@versions.size} versions on Docker Hub"

      failed_versions = []

      @versions.each do |version|
        begin
          extract_version(version)
        rescue => e
          puts "  ERROR: #{e.message}"
          failed_versions << version
        end
      end

      if failed_versions.any?
        raise "\n\nFailed to extract #{failed_versions.size} version(s): #{failed_versions.join(', ')}"
      end
    end

    # Extract a specific version
    def extract_version(version)
      pull_docker_image(version)
      extract_from_container(version)
      # Clean up the Docker image immediately to save disk space
      system("docker", "rmi", "-f", "#{DOCKER_IMAGE}:#{version}", out: File::NULL)
    end

    # Clean up Docker images in batches of 5, keeping the last one for caching
    def cleanup_docker_images
      images = `docker images --format "{{.Repository}}:{{.Tag}}" | grep "^#{DOCKER_IMAGE}" | grep -E "^[0-9]" | sort -V`.split("\n")

      # Keep the last one for caching, remove the rest in batches of 5
      return if images.size <= 1

      to_remove = images[0..-2] # Keep last one
      batches = to_remove.each_slice(5).to_a

      puts "\nCleaning up Docker images..."
      batches.each_with_index do |batch, i|
        puts "  Removing batch #{i + 1}/#{batches.size}..."
        system("docker", "rmi", "-f", *batch, out: File::NULL)
      end

      puts "  Kept for caching: #{images.last}"
    end
  end
end

# CLI interface
if __FILE__ == $PROGRAM_NAME
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
end
