# frozen_string_literal: true

require 'thor'
require 'json'
require_relative 'version'
require_relative 'models'
require_relative 'commands'
require_relative 'json_formatter'
require_relative 'gemfile_repository'
require_relative 'snap_repository'
require_relative 'homebrew_repository'
require_relative 'chocolatey_repository'

module Mnenv
  class Cli < Thor
    package_name 'mnenv'

    # Platform subcommands
    desc 'gemfile SUBCOMMAND', 'Manage Ruby (Gemfile) versions'
    subcommand 'gemfile', GemfileCommand

    desc 'snap SUBCOMMAND', 'Manage Snap versions'
    subcommand 'snap', SnapCommand

    desc 'homebrew SUBCOMMAND', 'Manage Homebrew versions'
    subcommand 'homebrew', HomebrewCommand

    desc 'chocolatey SUBCOMMAND', 'Manage Chocolatey versions'
    subcommand 'chocolatey', ChocolateyCommand

    # General commands
    PLATFORM_REPOSITORIES = {
      'gemfile' => GemfileRepository,
      'snap' => SnapRepository,
      'homebrew' => HomebrewRepository,
      'chocolatey' => ChocolateyRepository
    }.freeze

    desc 'info PLATFORM VERSION', 'Get details for a specific version'
    method_option :format, type: :string, aliases: '-f', default: 'json'
    def info(platform, version_number)
      repo_class = PLATFORM_REPOSITORIES[platform]
      unless repo_class
        puts "Error: Unknown platform '#{platform}'. Available: #{PLATFORM_REPOSITORIES.keys.join(', ')}"
        exit 1
      end

      repo = repo_class.new
      version_obj = repo.find(version_number)

      unless version_obj
        puts "Error: Version '#{version_number}' not found for platform '#{platform}'"
        exit 1
      end

      case options[:format]
      when 'json'
        require_relative 'json_formatter'
        require 'json'
        output = JsonFormatter.format_version(version_obj)
        output['platform'] = platform
        puts JSON.pretty_generate(output)
      else
        puts "#{platform.capitalize} version #{version_obj.display_name}:"
        puts "  Version: #{version_obj.version}"
        puts "  Published: #{version_obj.published_at || 'N/A'}"
        puts "  Parsed: #{version_obj.parsed_at || 'N/A'}"
        version_obj.to_h.each do |k, v|
          next if %w[version published_at parsed_at].include?(k)
          puts "  #{k}: #{v}"
        end
      end
    end

    desc 'list PLATFORM', 'List versions for a platform'
    method_option :format, type: :string, aliases: '-f', default: 'json'
    def list(platform)
      repo_class = PLATFORM_REPOSITORIES[platform]
      unless repo_class
        puts "Error: Unknown platform '#{platform}'. Available: #{PLATFORM_REPOSITORIES.keys.join(', ')}"
        exit 1
      end

      repo = repo_class.new
      versions = repo.all

      case options[:format]
      when 'json'
        output = JsonFormatter.format_versions(versions)
        output['platform'] = platform
        puts JSON.pretty_generate(output)
      else
        puts "#{platform.capitalize} versions (#{versions.size}):"
        versions.each do |v|
          published = v.published_at ? " (#{v.published_at.strftime('%Y-%m-%d')})" : ''
          puts "  #{v.display_name}#{published}"
        end
      end
    end

    desc 'list-all', 'List all versions from all platforms'
    method_option :format, type: :string, aliases: '-f', default: 'json'
    def list_all
      case options[:format]
      when 'json'
        output = {}
        PLATFORM_REPOSITORIES.each do |name, repo_class|
          repo = repo_class.new
          output[name] = JsonFormatter.format_versions(repo.all)
        end

        puts JSON.pretty_generate(output)
      else
        PLATFORM_REPOSITORIES.each_key do |platform|
          list(platform)
        end
      end
    end

    desc 'version', 'Show mnenv version'
    def version
      puts "mnenv #{Mnenv::VERSION}"
    end
  end
end
