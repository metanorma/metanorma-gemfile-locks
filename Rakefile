# frozen_string_literal: true

require "rake/clean"
require "yaml"

namespace :extract do
  desc "Extract missing versions (incremental)"
  task :incremental do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :incremental)
    extractor.extract_incremental
  end

  desc "Replace a single version (e.g., rake extract:replace[1.14.4])"
  task :replace, [:version] do |_t, args|
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :replace)
    extractor.extract_replace(args[:version])
  end

  desc "Re-extract all versions (revamp)"
  task :revamp do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :revamp)
    extractor.extract_revamp
  end

  desc "Extract Gemfile/Gemfile.lock for a specific version (e.g., rake extract[1.14.4])"
  task :version, [:version] do |_t, args|
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :replace)
    extractor.extract_replace(args[:version])
  end

  desc "Extract all available versions from Docker Hub"
  task :all do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :revamp)
    extractor.extract_revamp
  end
end

namespace :list do
  desc "List all available versions on Docker Hub"
  task :versions do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    versions = extractor.fetch_docker_hub_versions
    puts "Available versions on Docker Hub:"
    versions.each { |v| puts "  #{v.name}" }
  end

  desc "List all locally extracted versions"
  task :local do
    versions = Dir.glob("v*").sort.map { |d| File.basename(d)[1..] }
    puts "Local versions:"
    versions.each { |v| puts "  #{v}" }
    puts "Total: #{versions.size} versions"
  end

  desc "Check for version gaps between local and Docker Hub"
  task :gaps do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    remote_versions = extractor.fetch_docker_hub_versions.map(&:name)
    local_versions = Dir.glob("v*").sort.map { |d| File.basename(d)[1..] }

    missing = remote_versions - local_versions

    if missing.empty?
      puts "No gaps: All Docker Hub versions are present locally"
    else
      puts "Missing #{missing.size} version(s):"
      missing.each { |v| puts "  #{v}" }
    end
  end
end

namespace :generate do
  desc "Generate index.yaml with all versions"
  task :index do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    extractor.generate_index
  end
end

namespace :docker do
  desc "Clean up Docker images in batches of 5 (keeps last one for caching)"
  task :clean do
    images = `docker images --format "{{.Repository}}:{{.Tag}}" | grep "^metanorma/metanorma" | grep -E "^[0-9]" | sort -V`.split("\n")

    # Keep the last one for caching, remove the rest in batches of 5
    to_remove = images[0..-2] # Keep last one
    batches = to_remove.each_slice(5).to_a

    batches.each_with_index do |batch, i|
      puts "Removing batch #{i + 1}/#{batches.size}..."
      system("docker", "rmi", "-f", *batch)
    end

    puts "Docker cleanup complete. Kept: #{images.last}"
  end
end

namespace :test do
  desc "Test extraction with 3 containers to tmp/test_output"
  task :extract do
    require_relative "lib/metanorma_gemfile_locks"
    require "fileutils"

    versions_dir = File.join(Dir.pwd, "tmp", "test_output", "v")
    FileUtils.mkdir_p(versions_dir)

    extractor = MetanormaGemfileLocks::Extractor.new(
      mode: :revamp,
      versions_dir: versions_dir
    )

    extractor.extract_test(limit: 3)

    # Generate and verify index
    index_path = extractor.index_path
    index = MetanormaGemfileLocks::Index.new(index_path)

    remote_tags = extractor.fetch_docker_hub_versions
    local_version_objs = extractor.local_versions

    tag_info_by_version = remote_tags.each_with_object({}) { |ti, h| h[ti.name] = ti }

    local_version_objs.each do |version|
      tag_info = tag_info_by_version[version.number]
      published_at = tag_info&.published_at || File.stat(version.directory_path).mtime.iso8601
      parsed_at = Time.now.utc.iso8601

      version.instance_variable_set(:@published_at, published_at)
      version.instance_variable_set(:@parsed_at, parsed_at)
      index.add_version(version)
    end

    missing = remote_tags.map(&:name) - local_version_objs.map(&:number)
    index.save(remote_tags.size, missing)

    puts "Test complete! Extracted #{local_version_objs.size} versions"
    puts "Index generated at: #{index_path}"

    # Verify index.yaml structure
    index_data = YAML.load_file(index_path)
    first_version = index_data["versions"].first

    if first_version && first_version["published_at"] && first_version["parsed_at"]
      puts "Index structure verified: published_at and parsed_at present"
    else
      raise "Index structure invalid!"
    end
  end
end

desc "Extract all lock files"
task extract: "extract:all"

desc "List available versions"
task list: "list:versions"

desc "Generate index.yaml"
task generate_index: "generate:index"
