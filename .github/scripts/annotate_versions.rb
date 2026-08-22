#!/usr/bin/env ruby
# frozen_string_literal: true

# Annotate data/gemfile/versions.yaml with release provenance (ci#367).
#
# Usage: ruby annotate_versions.rb VERSION CREATED_AT_ISO RUN_ID RUN_URL [PATH]
# Default PATH: data/gemfile/versions.yaml
#
# Text-surgical (no full-file reserialize): appends or merges
# rubygems_created_at + release_provenance on a version entry, updates
# metadata.count/latest_version only when appending. Idempotent on
# already-annotated entries. Exits non-zero on structural surprises —
# never silently corrupts. Stdlib only.

require "date"

VERSION_RE = /^- version: (\S+)\s*$/

def vkey(v)
  v.sub(/\Av/, "").split(".").map { |x| x[/\A\d+/] && Integer(x) }
end

def main
  if ARGV.length < 4
    warn "usage: annotate_versions.rb VERSION CREATED_AT RUN_ID RUN_URL [PATH] [--via V] [--annotation TXT]"
    exit 2
  end
  via = "workflow"
  annotation = "rubygems-release.yml post-publish writer (ci#367)"
  pos = ARGV.reject do |a|
    if a == "--via"
      via = ARGV[ARGV.index(a) + 1]
      next true
    elsif a == "--annotation"
      annotation = ARGV[ARGV.index(a) + 1]
      next true
    elsif ARGV.index(a).to_i > 0 && %w[--via --annotation].include?(ARGV[ARGV.index(a) - 1])
      next true
    end
    false
  end
  ver, created, run_id, run_url = pos[0, 4]
  path = pos[4] || File.join("data", "gemfile", "versions.yaml")
  ver = ver.sub(/\Av/, "")
  src = File.read(path, encoding: "UTF-8")

  matches = src.enum_for(:scan, VERSION_RE).map { Regexp.last_match }
  if matches.empty?
    abort "no version entries found — refusing to touch file"
  end

  now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  provenance = <<~PROV
    rubygems_created_at: '#{created}'
      release_provenance:
        published_via: #{via}
        workflow_run_id: #{run_id}
        workflow_url: #{run_url}
        annotation: '#{annotation}'
  PROV

  existing = matches.find { |m| m[1] == ver }
  if existing
    nxt = src.match(VERSION_RE, existing.end(0))
    block_end = nxt ? nxt.begin(0) : src.length
    block = src[existing.begin(0)...block_end]
    if block.include?("release_provenance:")
      puts "entry #{ver} already annotated — no change"
    else
      stripped = block.sub(/\s+\z/, "")
      trailing = block[stripped.length..] || ""
      # provenance lines are indented two spaces; strip the heredoc's base indent
      fields = provenance.lines.each_with_index.map { |l, i| i.zero? ? "  #{l}" : l }.join
      new_block = "#{stripped}\n#{fields.sub(/\n\z/, '')}"
      File.write(path, "#{src[0...existing.begin(0)]}#{new_block}#{trailing}#{src[block_end..]}",
                 encoding: "UTF-8")
      puts "annotated existing entry #{ver}"
    end
    return
  end

  # New entry — schema-valid with gemfile_exists: false (docker channel
  # fills paths on the next mnenv refresh).
  entry = <<~ENTRY
    - version: #{ver}
      published_at: null
      parsed_at: '#{now}'
      gemfile_exists: false
      gemfile_path: null
      gemfile_lock_path: null
  ENTRY
  entry += provenance.lines.each_with_index.map { |l, i| i.zero? ? "  #{l}" : l }.join
  entry = entry.sub(/\n+\z/, "\n")

  out = src.sub(/\n+\z/, "\n") + entry

  out = out.sub(/^  count: (\d+)$/) { format("  count: %d", Regexp.last_match(1).to_i + 1) }

  latest = out.match(/^  latest_version: (\S+)$/)
  if latest && (vkey(ver) <=> vkey(latest[1])) == 1
    out = out.sub(latest[0], "  latest_version: #{ver}")
  end

  File.write(path, out, encoding: "UTF-8")
  puts "appended new entry #{ver}; count/latest updated"
end

main
