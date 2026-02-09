# frozen_string_literal: true

##
# Extract Gemfile and Gemfile.lock from metanorma/metanorma Docker images

require "fileutils"
require "json"
require "open-uri"
require "yaml"

module MetanormaGemfileLocks
  DOCKER_IMAGE = "metanorma/metanorma".freeze
  VERSIONS_DIR = File.join(__dir__, "..", "v").freeze
  INDEX_PATH = File.join(File.dirname(VERSIONS_DIR), "index.yaml").freeze

  # Represents a single version with its metadata
  class Version
    attr_reader :number, :updated_at

    def initialize(number, updated_at = nil)
      @number = number
      @updated_at = updated_at
    end

    def <=>(other)
      version_parts <=> other.version_parts
    end

    def version_parts
      @version_parts ||= number.split(".").map(&:to_i)
    end

    def directory_path
      @directory_path ||= File.join(File.dirname(VERSIONS_DIR), "v#{number}")
    end

    def gemfile_path
      @gemfile_path ||= File.join(directory_path, "Gemfile")
    end

    def gemfile_lock_path
      @gemfile_lock_path ||= File.join(directory_path, "Gemfile.lock")
    end

    def exists_locally?
      File.file?(gemfile_path) && File.file?(gemfile_lock_path)
    end

    def to_h
      { "version" => number, "updated_at" => updated_at }
    end
  end

  # Manages index.yaml file operations
  class Index
    attr_reader :versions, :metadata

    def initialize(path = INDEX_PATH)
      @path = path
      @versions = {}
      @metadata = {}
      load if File.file?(path)
    end

    def load
      data = YAML.load_file(@path) || {}
      @metadata = data["metadata"] || {}
      @versions = (data["versions"] || []).each_with_object({}) do |v, h|
        h[v["version"]] = v["updated_at"]
      end
    end

    def get_updated_at(version_number)
      @versions[version_number]
    end

    def add_version(version)
      @versions[version.number] = version.updated_at
    end

    def latest_version
      @versions.keys.max_by { |v| v.split(".").map(&:to_i) }
    end

    def version_count
      @versions.size
    end

    def to_h(remote_count, missing_versions)
      versions_array = @versions.keys.sort_by { |v| v.split(".").map(&:to_i) }.map do |version|
        { "version" => version, "updated_at" => @versions[version] }
      end

      {
        "metadata" => {
          "generated_at" => Time.now.utc.iso8601,
          "local_count" => version_count,
          "remote_count" => remote_count,
          "latest_version" => latest_version
        },
        "missing_versions" => missing_versions,
        "versions" => versions_array
      }
    end

    def save(remote_count, missing_versions)
      File.write(@path, to_h(remote_count, missing_versions).to_yaml)
    end
  end

  # Extracts Gemfile and Gemfile.lock from Docker containers
  class Extractor
    def initialize(index = nil)
      @index = index || Index.new
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

      versions.sort_by { |v| v.split(".").map(&:to_i) }
    end

    # Pull a Docker image for a specific version
    def pull_docker_image(version)
      puts "Pulling #{DOCKER_IMAGE}:#{version}..."
      system("docker", "pull", "#{DOCKER_IMAGE}:#{version}")
    end

    # Extract Gemfile and Gemfile.lock from a Docker container
    def extract_from_container(version)
      version_obj = Version.new(version)
      FileUtils.mkdir_p(version_obj.directory_path)

      extract_script = <<~SCRIPT
        #!/bin/sh
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
        exit 1
      SCRIPT

      cmd = <<~CMD
        docker run --rm --entrypoint sh #{DOCKER_IMAGE}:#{version} -c '#{extract_script}'
      CMD

      output = `#{cmd}`
      status = $?.exitstatus

      if status != 0 || output.include?("ERROR: No Gemfile found")
        raise "Failed to extract Gemfile from version #{version}:\n#{output}"
      end

      parts = output.split("===GEMFILE.EOF===")
      if parts.size < 2
        raise "Failed to parse Gemfile output for version #{version}"
      end

      gemfile_content = parts[0].sub(/GEMFILE_DIR=.+\n/, "")
      gemfile_lock_content = parts[1]

      File.write(version_obj.gemfile_path, gemfile_content.strip + "\n")
      File.write(version_obj.gemfile_lock_path, gemfile_lock_content.strip + "\n")

      gemfile_dir = output[/GEMFILE_DIR=(.+)/, 1]
      puts "  Extracted to v#{version}/ (from #{gemfile_dir})"
    end

    # Extract a specific version
    def extract_version(version)
      version_obj = Version.new(version)

      # Skip if already extracted locally
      if version_obj.exists_locally?
        puts "Skipping v#{version}/ (already exists)"
        return
      end

      pull_docker_image(version)
      extract_from_container(version)
      system("docker", "rmi", "-f", "#{DOCKER_IMAGE}:#{version}", out: File::NULL)
    end

    # Extract all versions
    def extract_all
      versions = fetch_docker_hub_versions
      puts "Found #{versions.size} versions on Docker Hub"

      failed_versions = []

      versions.each do |version|
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

    # Get list of locally extracted versions as Version objects
    def local_versions
      Dir.glob(File.join(File.dirname(VERSIONS_DIR), "v*")).map do |d|
        version_number = File.basename(d)[1..]
        version = Version.new(version_number)

        if version.exists_locally?
          version
        else
          warn "Skipping v#{version_number}: missing Gemfile or Gemfile.lock"
          nil
        end
      end.compact
    end

    # Generate index.yaml with all versions
    def generate_index
      remote_versions = fetch_docker_hub_versions
      local_version_objs = local_versions

      # Update index with local versions, preserving existing timestamps
      local_version_objs.each do |version|
        existing_timestamp = @index.get_updated_at(version.number)
        timestamp = existing_timestamp || File.stat(version.directory_path).mtime.iso8601
        version.instance_variable_set(:@updated_at, timestamp)
        @index.add_version(version)
      end

      missing = remote_versions - local_version_objs.map(&:number)

      @index.save(remote_versions.size, missing)
      puts "Generated index.yaml with #{local_version_objs.size} versions"
    end

    # Clean up Docker images in batches of 5, keeping the last one for caching
    def cleanup_docker_images
      images = `docker images --format "{{.Repository}}:{{.Tag}}" | grep "^#{DOCKER_IMAGE}" | grep -E "^[0-9]" | sort -V`.split("\n")

      return if images.size <= 1

      to_remove = images[0..-2]
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
