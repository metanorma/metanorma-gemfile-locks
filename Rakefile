# frozen_string_literal: true

require "rake/clean"
require "yaml"

namespace :extract do
  desc "Extract Gemfile/Gemfile.lock for a specific version (e.g., rake extract[1.14.4])"
  task :version, [:version] do |_t, args|
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    extractor.extract_version(args[:version])
  end

  desc "Extract all available versions from Docker Hub"
  task :all do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    extractor.extract_all
  end
end

namespace :list do
  desc "List all available versions on Docker Hub"
  task :versions do
    require_relative "lib/metanorma_gemfile_locks"
    extractor = MetanormaGemfileLocks::Extractor.new
    versions = extractor.fetch_docker_hub_versions
    puts "Available versions on Docker Hub:"
    versions.each { |v| puts "  #{v}" }
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
    remote_versions = extractor.fetch_docker_hub_versions
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

desc "Extract all lock files"
task extract: "extract:all"

desc "List available versions"
task list: "list:versions"

desc "Generate index.yaml"
task generate_index: "generate:index"
