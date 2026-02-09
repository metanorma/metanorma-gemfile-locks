# frozen_string_literal: true

##
# Extract Gemfile and Gemfile.lock from metanorma/metanorma Docker images

require "fileutils"
require "json"
require "open-uri"
require "yaml"

require_relative "metanorma_gemfile_locks/logger"

module MetanormaGemfileLocks
  DOCKER_IMAGE = "metanorma/metanorma".freeze
  VERSIONS_DIR = File.join(__dir__, "..", "v").freeze
  INDEX_PATH = File.join(File.dirname(VERSIONS_DIR), "index.yaml").freeze

  # Docker Hub tag metadata from API
  class TagInfo
    attr_reader :name, :published_at

    def initialize(name, published_at)
      @name = name
      @published_at = published_at
    end
  end

  # Represents a single version with its metadata
  class Version
    attr_reader :number, :published_at, :parsed_at

    # For backwards compatibility
    alias updated_at published_at

    def initialize(number, published_at: nil, parsed_at: nil, versions_dir: VERSIONS_DIR)
      @number = number
      @published_at = published_at
      @parsed_at = parsed_at
      @versions_dir = versions_dir
    end

    def versions_dir
      @versions_dir || VERSIONS_DIR
    end

    def <=>(other)
      version_parts <=> other.version_parts
    end

    def version_parts
      @version_parts ||= number.split(".").map(&:to_i)
    end

    def directory_path
      @directory_path ||= File.join(File.dirname(versions_dir), "v#{number}")
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
      { "version" => number, "published_at" => published_at, "parsed_at" => parsed_at }
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
      @versions = {}

      (data["versions"] || []).each do |v|
        # Handle migration from old format
        if v.key?("updated_at")
          @versions[v["version"]] = { "published_at" => v["updated_at"], "parsed_at" => v["parsed_at"] }
        else
          @versions[v["version"]] = { "published_at" => v["published_at"], "parsed_at" => v["parsed_at"] }
        end
      end
    end

    def get_published_at(version_number)
      @versions.dig(version_number, "published_at")
    end

    def get_parsed_at(version_number)
      @versions.dig(version_number, "parsed_at")
    end

    # For backwards compatibility
    def get_updated_at(version_number)
      get_published_at(version_number)
    end

    def add_version(version)
      @versions[version.number] = { "published_at" => version.published_at, "parsed_at" => version.parsed_at }
    end

    def latest_version
      @versions.keys.max_by { |v| v.split(".").map(&:to_i) }
    end

    def version_count
      @versions.size
    end

    def to_h(remote_count, missing_versions)
      versions_array = @versions.keys.sort_by { |v| v.split(".").map(&:to_i) }.map do |version|
        { "version" => version, "published_at" => @versions[version]["published_at"], "parsed_at" => @versions[version]["parsed_at"] }
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
    ExtractionMode = %i[incremental replace revamp].freeze

    def initialize(mode: :incremental, index: nil, versions_dir: VERSIONS_DIR, limit: nil)
      @mode = mode || :incremental
      @index = index || Index.new
      @tag_info_cache = {}
      @versions_dir = versions_dir
      @limit = limit
    end

    # Get the versions directory (allows custom output location)
    def versions_dir
      @versions_dir || VERSIONS_DIR
    end

    # Get index path based on versions directory
    def index_path
      File.join(File.dirname(versions_dir), "index.yaml")
    end

    # Fetch all version tags from Docker Hub
    def fetch_docker_hub_versions
      uri = URI("https://registry.hub.docker.com/v2/repositories/#{DOCKER_IMAGE}/tags?page_size=100")
      tag_info_list = []

      loop do
        data = JSON.parse(URI.open(uri).read)
        data["results"].each do |result|
          name = result["name"]
          if name =~ /^\d+\.\d+\.\d+$/
            # Docker Hub API: tag_last_pushed is when tag was published
            published_at = result["tag_last_pushed"]
            tag_info_list << TagInfo.new(name, published_at)
          end
        end

        break unless data["next"]
        uri = URI(data["next"])
      end

      tag_info_list.sort_by { |t| t.name.split(".").map(&:to_i) }
    end

    # Cache Docker Hub tag info for all versions
    def cache_tag_info
      @tag_info_cache = fetch_docker_hub_versions.each_with_object({}) do |tag_info, h|
        h[tag_info.name] = tag_info
      end
    end

    def extract_incremental
      cache_tag_info
      local_version_numbers = local_versions.map(&:number)

      @tag_info_cache.each_value do |tag_info|
        next if local_version_numbers.include?(tag_info.name)
        extract_version(tag_info.name, tag_info: tag_info)
      end
    end

    def extract_replace(version_number)
      cache_tag_info
      tag_info = @tag_info_cache[version_number]

      raise "Version #{version_number} not found on Docker Hub" unless tag_info

      # Remove existing files if present
      version_obj = Version.new(version_number)
      if version_obj.exists_locally?
        FileUtils.rm_f([version_obj.gemfile_path, version_obj.gemfile_lock_path])
      end

      extract_version(version_number, tag_info: tag_info)
    end

    def extract_revamp
      cache_tag_info

      @tag_info_cache.each_value do |tag_info|
        extract_version(tag_info.name, tag_info: tag_info)
      end
    end

    # Extract a limited number of versions for testing
    def extract_test(limit: 3)
      cache_tag_info

      # Get the latest N versions
      versions_to_extract = @tag_info_cache.values.last(limit)

      Logger.header "Test mode: Extracting #{versions_to_extract.size} versions"

      versions_to_extract.each do |tag_info|
        extract_version(tag_info.name, tag_info: tag_info)
      end
    end

    # Pull a Docker image for a specific version
    def pull_docker_image(version)
      Logger.pulling(version)
      system("docker", "pull", "#{DOCKER_IMAGE}:#{version}")
    end

    # Extract Gemfile and Gemfile.lock from a Docker container
    def extract_from_container(version)
      version_obj = Version.new(version, versions_dir: versions_dir)
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
      Logger.extracted(version, from: gemfile_dir)
    end

    # Extract a specific version
    def extract_version(version, tag_info: nil)
      version_obj = Version.new(
        version,
        published_at: tag_info&.published_at,
        parsed_at: Time.now.utc.iso8601,
        versions_dir: versions_dir
      )

      # Skip incremental if already extracted (unless forced)
      if @mode == :incremental && version_obj.exists_locally?
        Logger.skipping(version)
        return version_obj
      end

      pull_docker_image(version)
      extract_from_container(version)
      system("docker", "rmi", "-f", "#{DOCKER_IMAGE}:#{version}", out: File::NULL)

      version_obj
    end

    # Extract all versions
    def extract_all
      versions = fetch_docker_hub_versions.map(&:name)
      Logger.info "Found #{versions.size} versions on Docker Hub"

      failed_versions = []

      versions.each do |version|
        begin
          extract_version(version)
        rescue => e
          Logger.error e.message
          failed_versions << version
        end
      end

      if failed_versions.any?
        raise "\n\nFailed to extract #{failed_versions.size} version(s): #{failed_versions.join(', ')}"
      end
    end

    # Get list of locally extracted versions as Version objects
    def local_versions
      Dir.glob(File.join(File.dirname(versions_dir), "v*")).map do |d|
        version_number = File.basename(d)[1..]
        version = Version.new(version_number, versions_dir: versions_dir)

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
      remote_tags = fetch_docker_hub_versions
      local_version_objs = local_versions

      # Build tag info cache
      tag_info_by_version = remote_tags.each_with_object({}) { |ti, h| h[ti.name] = ti }

      local_version_objs.each do |version|
        # Prefer Docker Hub published_at, fallback to existing, then file mtime
        tag_info = tag_info_by_version[version.number]
        published_at = tag_info&.published_at ||
                     @index.get_published_at(version.number) ||
                     File.stat(version.directory_path).mtime.iso8601

        # Use existing parsed_at or set to now
        parsed_at = @index.get_parsed_at(version.number) ||
                    (tag_info ? Time.now.utc.iso8601 : nil)

        version.instance_variable_set(:@published_at, published_at)
        version.instance_variable_set(:@parsed_at, parsed_at)
        @index.add_version(version)
      end

      missing = remote_tags.map(&:name) - local_version_objs.map(&:number)
      @index.save(remote_tags.size, missing)
      Logger.success "Generated index.yaml with #{local_version_objs.size} versions"
    end

    # Clean up Docker images in batches of 5, keeping the last one for caching
    def cleanup_docker_images
      images = `docker images --format "{{.Repository}}:{{.Tag}}" | grep "^#{DOCKER_IMAGE}" | grep -E "^[0-9]" | sort -V`.split("\n")

      return if images.size <= 1

      to_remove = images[0..-2]
      batches = to_remove.each_slice(5).to_a

      Logger.header "Cleaning up Docker images"
      batches.each_with_index do |batch, i|
        Logger.section "Removing batch #{i + 1}/#{batches.size}"
        system("docker", "rmi", "-f", *batch, out: File::NULL)
      end

      Logger.info "Kept for caching: #{images.last}"
    end
  end
end
