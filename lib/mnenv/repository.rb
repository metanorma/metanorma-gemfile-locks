# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Mnenv
  class Repository
    attr_reader :data_dir, :versions_file_path

    def initialize(data_dir: nil)
      @data_dir = data_dir || default_data_dir
      @versions_file_path = File.join(@data_dir, 'versions.yaml')
      @versions_cache = {}
      load if File.file?(versions_file_path)
    end

    def find(version_number) = @versions_cache[version_number]

    def all = @versions_cache.values.sort

    def latest = all.last

    def count = @versions_cache.size

    def exists?(version_number) = @versions_cache.key?(version_number)

    def save(version)
      @versions_cache[version.version] = version
      persist
    end

    def save_all(versions)
      versions.each { |v| @versions_cache[v.version] = v }
      persist
    end

    protected

    def load
      data = YAML.load_file(versions_file_path)
      return if data.nil? || data['versions'].nil?

      data['versions'].each do |version_hash|
        version = version_class.new(version_hash)
        @versions_cache[version.version] = version
      end
    end

    def persist
      FileUtils.mkdir_p(data_dir)
      output = {
        'metadata' => metadata,
        'versions' => @versions_cache.values.sort.map { |v| version_to_hash(v) }
      }
      File.write(versions_file_path, output.to_yaml)
    end

    def metadata
      {
        'generated_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'source' => source_name,
        'count' => count,
        'latest_version' => latest&.version
      }
    end

    def version_class = raise NotImplementedError

    def source_name = raise NotImplementedError

    def default_data_dir = File.join(__dir__, '..', '..', 'data', source_name.to_s)

    private

    def version_to_hash(version)
      hash = {
        'version' => version.version,
        'published_at' => format_timestamp(version.published_at),
        'parsed_at' => format_timestamp(version.parsed_at)
      }

      # Add subclass-specific fields
      case version
      when GemfileVersion
        hash['gemfile_exists'] = version.gemfile_exists
        hash['gemfile_path'] = version.gemfile_path
        hash['gemfile_lock_path'] = version.gemfile_lock_path
      when SnapVersion
        hash['revision'] = version.revision
        hash['arch'] = version.arch
        hash['channel'] = version.channel
      when HomebrewVersion
        hash['tag_name'] = version.tag_name
        hash['commit_sha'] = version.commit_sha
      when ChocolateyVersion
        hash['package_name'] = version.package_name
        hash['is_pre_release'] = version.is_pre_release
      end

      hash
    end

    def format_timestamp(t) = t&.strftime('%Y-%m-%dT%H:%M:%SZ')
  end
end
