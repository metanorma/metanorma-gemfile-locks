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

      # Create a temporary container
      container_name = "metanorma-extract-#{version}"

      # Start container in background
      system("docker", "run", "-d", "--name", container_name,
             "#{DOCKER_IMAGE}:#{version}", "sleep", "3600", out: File::NULL)

      begin
        # Try multiple possible Gemfile locations
        # Newer versions use /setup/Gemfile, older versions use /Gemfile
        gemfile_locations = ["/setup/Gemfile", "/Gemfile"]
        gemfile_path = nil

        gemfile_locations.each do |location|
          result = system("docker", "exec", container_name, "test", "-f", location, out: File::NULL)
          if result
            gemfile_path = location
            break
          end
        end

        if gemfile_path.nil?
          puts "  Warning: Could not find Gemfile in container, skipping v#{version}/"
          return
        end

        # Extract directory path (e.g., /setup/ or /)
        extract_dir = gemfile_path.sub("Gemfile", "")

        # Copy Gemfile
        system("docker", "cp", "#{container_name}:#{gemfile_path}",
               File.join(version_dir, "Gemfile"))

        # Copy Gemfile.lock (ensure proper path with trailing slash)
        gemfile_lock_path = extract_dir.end_with?("/") ? "#{extract_dir}Gemfile.lock" : "#{extract_dir}/Gemfile.lock"
        system("docker", "cp", "#{container_name}:#{gemfile_lock_path}",
               File.join(version_dir, "Gemfile.lock"))

        puts "  Extracted to v#{version}/ (from #{extract_dir})"
      ensure
        # Remove container
        system("docker", "rm", "-f", container_name, out: File::NULL)
      end
    end

    # Extract all versions
    def extract_all
      @versions = fetch_docker_hub_versions
      puts "Found #{@versions.size} versions on Docker Hub"

      @versions.each do |version|
        extract_version(version)
      end

      # Clean up Docker images in batches of 5, keeping the last one for caching
      cleanup_docker_images
    end

    # Extract a specific version
    def extract_version(version)
      pull_docker_image(version)
      extract_from_container(version)
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
