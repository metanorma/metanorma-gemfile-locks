# frozen_string_literal: true

require "paint"

module MetanormaGemfileLocks
  class Logger
    # Emojis for different log levels
    EMOJIS = {
      info: "ℹ️",
      success: "✅",
      warning: "⚠️",
      error: "❌",
      pulling: "📥",
      extracting: "📦",
      skipping: "⏭️",
      cleaning: "🧹"
    }.freeze

    class << self
      def info(message)
        puts Paint["#{EMOJIS[:info]} #{message}", :cyan]
      end

      def success(message)
        puts Paint["#{EMOJIS[:success]} #{message}", :green]
      end

      def warning(message)
        warn Paint["#{EMOJIS[:warning]} WARNING: #{message}", :yellow]
      end

      def error(message)
        warn Paint["#{EMOJIS[:error]} ERROR: #{message}", :red, :bold]
      end

      def pulling(version)
        puts Paint["#{EMOJIS[:pulling]} Pulling #{MetanormaGemfileLocks::DOCKER_IMAGE}:#{version}...", :blue]
      end

      def extracted(version, from:)
        puts Paint["  #{EMOJIS[:extracting]} Extracted to v#{version}/ (from #{from})", :green]
      end

      def skipping(version)
        puts Paint["  #{EMOJIS[:skipping]} Skipping v#{version}/ (already exists)", :yellow]
      end

      def header(message)
        puts "\n" + Paint["=== #{message} ===", :bold, :white] + "\n"
      end

      def section(message)
        puts Paint["▸ #{message}", :cyan]
      end

      def sub(message)
        puts Paint["  • #{message}", :gray]
      end
    end
  end
end
