#!/usr/bin/env ruby
# frozen_string_literal: true

##
# CLI to extract Gemfile and Gemfile.lock from metanorma/metanorma Docker images

require_relative "../lib/metanorma_gemfile_locks"
require "thor"

class MetanormaGemfileLocksCLI < Thor
  package_name "metanorma-gemfile-locks"

  desc "incremental", "Extract only missing versions (default)"
  def incremental
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :incremental)
    extractor.extract_incremental
  end

  desc "replace VERSION", "Replace a single version"
  def replace(version)
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :replace)
    extractor.extract_replace(version)
  end

  desc "revamp", "Re-extract all versions"
  def revamp
    extractor = MetanormaGemfileLocks::Extractor.new(mode: :revamp)
    extractor.extract_revamp
  end

  desc "list", "List available versions from Docker Hub"
  def list
    extractor = MetanormaGemfileLocks::Extractor.new
    tags = extractor.fetch_docker_hub_versions
    MetanormaGemfileLocks::Logger.header "Available versions"
    tags.each { |t| MetanormaGemfileLocks::Logger.sub "#{t.name} (#{t.published_at})" }
  end

  desc "test [OUTPUT_DIR]", "Extract 3 versions to a test directory (default: tmp/test_output)"
  def test(output_dir = "tmp/test_output")
    require "fileutils"

    # Create temp output directory
    versions_dir = File.join(Dir.pwd, output_dir, "v")
    FileUtils.mkdir_p(versions_dir)

    # Create extractor with custom versions_dir
    extractor = MetanormaGemfileLocks::Extractor.new(
      mode: :revamp,
      versions_dir: versions_dir
    )

    # Extract 3 versions
    extractor.extract_test(limit: 3)

    # Generate index
    index_path = extractor.index_path
    index = MetanormaGemfileLocks::Index.new(index_path)

    remote_tags = extractor.fetch_docker_hub_versions
    local_version_objs = extractor.local_versions

    # Build tag info cache
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

    MetanormaGemfileLocks::Logger.success "Test complete! Extracted #{local_version_objs.size} versions"
    MetanormaGemfileLocks::Logger.info "Index generated at: #{index_path}"

    # Verify index.yaml structure
    require "yaml"
    index_data = YAML.load_file(index_path)
    first_version = index_data["versions"].first

    if first_version && first_version["published_at"] && first_version["parsed_at"]
      MetanormaGemfileLocks::Logger.success "Index structure verified: published_at and parsed_at present"
    else
      MetanormaGemfileLocks::Logger.error "Index structure invalid!"
      exit 1
    end
  end

  default_task :incremental
end

MetanormaGemfileLocksCLI.start(ARGV)
