#!/usr/bin/env ruby
# frozen_string_literal: true

# Validate data/gemfile/versions.yaml against schemas/gemfile-versions.schema.json.
#
# Exits non-zero on any schema violation. Requires json_schemer
# (workflow installs it via `gem install json_schemer` — the repo is a
# pure-data repo with no Gemfile; the gem-install pattern matches
# `gem install gem-release` in metanorma/ci workflows).
#
# Usage: ruby .github/scripts/validate_versions.rb

require "yaml"
require "json"
require "json_schemer"

REPO_ROOT = File.expand_path("../..", __dir__)
SCHEMA_DIR = File.join(REPO_ROOT, "schemas")
DATA_FILE = File.join(REPO_ROOT, "data", "gemfile", "versions.yaml")
ROOT_SCHEMA = File.join(SCHEMA_DIR, "gemfile-versions.schema.json")

def load_schema(path)
  JSON.parse(File.read(path, encoding: "UTF-8"))
end

# File-based $ref resolution: schemas reference siblings by relative name.
# json_schemer resolves the ref against the root $id and hands us an
# absolute URI — map by basename into schemas/.
FILE_REF_RESOLVER = lambda do |ref|
  name = File.basename(ref.respond_to?(:path) ? ref.path : ref.to_s)
  target = File.join(SCHEMA_DIR, name)
  load_schema(target) if File.exist?(target)
end

def main
  [DATA_FILE, ROOT_SCHEMA].each do |p|
    abort "missing #{p}" unless File.exist?(p)
  end

  root_schema = load_schema(ROOT_SCHEMA)
  validator = JSONSchemer.schema(
    root_schema,
    ref_resolver: FILE_REF_RESOLVER,
    formats: JSONSchemer::Draft202012::FORMATS,
  )

  data = YAML.safe_load_file(DATA_FILE, permitted_classes: [Symbol])
  # The register writes `source: :gemfile` as a Ruby symbol; the schema
  # models it as a string (PyYAML-era semantics). Normalize before validating.
  if data.dig("metadata", "source").is_a?(Symbol)
    data["metadata"]["source"] = data["metadata"]["source"].to_s
  end
  errors = validator.validate(data).to_a
  if errors.empty?
    puts "OK — #{data.fetch("versions", []).length} version entries valid" \
         " against #{File.basename(ROOT_SCHEMA)}"
    return 0
  end

  warn "FAIL — #{errors.length} schema violation(s) in #{DATA_FILE}:"
  errors.first(50).each do |err|
    loc = err["data_pointer"].to_s.empty? ? "<root>" : err["data_pointer"]
    warn "  #{loc}: #{err["error"]}"
  end
  1
end

exit main
