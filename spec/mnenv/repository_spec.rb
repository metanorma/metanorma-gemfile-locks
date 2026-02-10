# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Mnenv::GemfileRepository do
  let(:data_dir) { Dir.mktmpdir }
  let(:repo) { described_class.new(data_dir: data_dir) }
  let(:versions_file) { File.join(data_dir, 'versions.yaml') }

  after { FileUtils.rm_rf(data_dir) }

  describe '#initialize' do
    it 'creates a new repository with data_dir' do
      expect(repo.data_dir).to eq(data_dir)
      expect(repo.versions_file_path).to eq(versions_file)
    end

    it 'creates empty cache when no versions file exists' do
      expect(repo.all).to eq([])
      expect(repo.count).to eq(0)
    end
  end

  describe '#save and #find' do
    it 'saves and retrieves a version' do
      version = Mnenv::ArtifactVersion.new(version: '1.2.3')
      repo.save(version)

      expect(repo.find('1.2.3')).to eq(version)
      expect(repo.exists?('1.2.3')).to be true
    end

    it 'persists versions to YAML file' do
      version = Mnenv::ArtifactVersion.new(version: '1.2.3')
      repo.save(version)

      # Create new repo instance to test persistence
      repo2 = described_class.new(data_dir: data_dir)
      expect(repo2.find('1.2.3').version).to eq('1.2.3')
    end
  end

  describe '#save_all' do
    it 'saves multiple versions' do
      versions = [
        Mnenv::ArtifactVersion.new(version: '1.2.3'),
        Mnenv::ArtifactVersion.new(version: '1.2.4'),
        Mnenv::ArtifactVersion.new(version: '1.3.0')
      ]

      repo.save_all(versions)

      expect(repo.count).to eq(3)
      expect(repo.all.map(&:version)).to eq(['1.2.3', '1.2.4', '1.3.0'])
    end
  end

  describe '#latest' do
    it 'returns the highest version' do
      versions = [
        Mnenv::ArtifactVersion.new(version: '1.2.3'),
        Mnenv::ArtifactVersion.new(version: '1.3.0'),
        Mnenv::ArtifactVersion.new(version: '1.2.4')
      ]

      repo.save_all(versions)

      expect(repo.latest.version).to eq('1.3.0')
    end

    it 'returns nil when no versions exist' do
      expect(repo.latest).to be_nil
    end
  end
end
