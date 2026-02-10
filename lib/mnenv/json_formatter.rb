# frozen_string_literal: true

require 'json'

module Mnenv
  class JsonFormatter
    def self.format_version(version)
      {
        'version' => version.version,
        'published_at' => format_timestamp(version.published_at),
        'parsed_at' => format_timestamp(version.parsed_at),
        'display_name' => version.display_name
      }.merge(version_specific_fields(version))
    end

    def self.format_versions(versions)
      {
        'count' => versions.size,
        'latest' => versions.last&.version,
        'versions' => versions.map { |v| format_version(v) }
      }
    end

    class << self
      def format_timestamp(t) = t&.strftime('%Y-%m-%dT%H:%M:%SZ')

      def version_specific_fields(version)
        case version
        when GemfileVersion
          { 'gemfile_exists' => version.exists_locally? }
        when SnapVersion
          { 'revision' => version.revision, 'channel' => version.channel }
        when HomebrewVersion
          { 'tag_name' => version.tag_name, 'commit_sha' => version.commit_sha }
        when ChocolateyVersion
          { 'package_name' => version.package_name, 'is_pre_release' => version.is_pre_release }
        else
          {}
        end
      end
    end
  end
end
