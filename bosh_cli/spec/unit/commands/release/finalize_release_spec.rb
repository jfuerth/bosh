require 'spec_helper'

module Bosh::Cli::Command::Release

  ORIG_DEV_VERSION = "8.1+dev.3"

  describe FinalizeRelease do
    subject(:command) { FinalizeRelease.new }

    describe '#finalize' do

      let(:release) { instance_double('Bosh::Cli::Release') }
      let(:file) {instance_double(File)}
      let(:tarball) { instance_double('Bosh::Cli::ReleaseTarball') }
      let(:blob_manager) { instance_double('Bosh::Cli::BlobManager') }
      let(:version_index) { instance_double('Bosh::Cli::Versions::VersionsIndex') }
      let(:release_version_index) { instance_double('Bosh::Cli::Versions::ReleaseVersionsIndex') }
      before do

        allow(command).to receive(:check_if_release_dir)
        allow(command).to receive(:release).and_return(release)

        allow(release).to receive(:save_config)
        allow(release).to receive(:latest_release_filename=)

        allow(File).to receive(:open).and_return(file)
        allow(file).to receive(:puts)

        allow(Bosh::Cli::ReleaseTarball).to receive(:new).and_return(tarball)
        allow(tarball).to receive(:manifest).and_return("{'name': 'my-release', 'version': '#{ORIG_DEV_VERSION}'}")
        allow(tarball).to receive(:exists?).and_return(true)
        allow(tarball).to receive(:perform_validation)
        allow(tarball).to receive(:version).and_return(ORIG_DEV_VERSION)
        allow(tarball).to receive(:replace_manifest)
        allow(tarball).to receive(:create_from_unpacked)

        allow(Bosh::Cli::BlobManager).to receive(:new).and_return(blob_manager)
        allow(blob_manager).to receive(:blobs_to_upload).and_return(%w(blobs/foo/pending_blob_1.tar.gz src/bar/pending_blob_2.tar.gz))
        allow(blob_manager).to receive(:upload_blob)

        allow(Bosh::Cli::Versions::VersionsIndex).to receive(:new).and_return(version_index)
        allow(version_index).to receive(:storage_dir).and_return(Dir.mktmpdir("foo") )
        allow(version_index).to receive(:version_strings)
        allow(version_index).to receive(:add_version)

        allow(Bosh::Cli::Versions::ReleaseVersionsIndex).to receive(:new).and_return(release_version_index)
        allow(release_version_index).to receive(:latest_version).and_return(Bosh::Common::Version::ReleaseVersion.parse('2'))
      end

      it 'is a command with the correct options' do
       command = Bosh::Cli::Config.commands['finalize release']
       expect(command).to have_options
       expect(command.options.map(&:first)).to match_array([
         '--dry-run',
         '--name NAME',
         '--version VERSION',
       ])
      end

      it 'fails when nonexistent tarball is specified' do
        allow(tarball).to receive(:exists?).and_return(false)
        expect { command.finalize('nonexistent.tgz') }.to raise_error(Bosh::Cli::CliError, 'Cannot find release tarball nonexistent.tgz')
      end

      it 'fails when given a final release tarball as input' do
        allow(tarball).to receive(:version).and_return("2")
        expect { command.finalize('ignored.tgz') }.to raise_error(Bosh::Cli::CliError, 'Release tarball already has final version 2')
      end

      it 'uses given name if --name is specified' do
        command.options[:name] = "custom-final-release-name"
        command.finalize('ignored.tgz')
        expect(tarball).to have_received(:replace_manifest).with(hash_including("name" => "custom-final-release-name"))
      end

      it 'uses name from tarball manifest if --name not specified' do
        command.finalize('ignored.tgz')
        expect(tarball).to have_received(:replace_manifest).with(hash_including("name" => "my-release"))
      end

      it 'uses given final version if --version is specified' do
        command.options[:version] = "77"
        command.finalize('ignored.tgz')
        expect(tarball).to have_received(:replace_manifest).with(hash_including("version" => "77"))
      end

      it 'uses next final release version if --version not specified' do
        command.finalize('ignored.tgz')
        expect(tarball).to have_received(:replace_manifest).with(hash_including("version" => "3"))
      end

      it 'if --version is specified and is already taken, show an already exists version error' do
        command.options[:version] = "3"
        local_artifact_storage = instance_double(Bosh::Cli::Versions::LocalArtifactStorage)
        allow(Bosh::Cli::Versions::LocalArtifactStorage).to receive(:new).and_return(local_artifact_storage)
        allow(local_artifact_storage).to receive(:has_file?).and_return(true)
        expect { command.finalize('ignored.tgz') }.to raise_error(Bosh::Cli::CliError, 'Release version already exists')
      end

      it 'creates the final release directory when it doesn''t exist' do
        command.options[:name] = "new-release-name"

        expect(FileUtils).to receive(:mkdir_p).with('releases/new-release-name')

        command.finalize('ignored.tgz')
      end

      it 'updates the latest release filename to point to the finalized release' do
        command.finalize('ignored.tgz')
        expect(release).to have_received(:latest_release_filename=).with('releases/my-release/my-release-3.yml')
        expect(release).to have_received(:save_config)
      end

      it 'saves the final release manifest into the release directory' do
        command.finalize('ignored.tgz')
        expect(file).to have_received(:puts).with("{'name': 'my-release', 'version': '8.1+dev.3'}")
      end

      it 'updates release index file' do
        command.options[:version] = "3"
        command.finalize('ignored.tgz')
        expect(version_index).to have_received(:add_version).with(anything, "version" => "3")
      end

      it 'creates the final release tarball' do
        command.finalize('ignored.tgz')
        expect(tarball).to have_received(:create_from_unpacked).with('releases/my-release/my-release-3.tgz')
      end

      it 'uploads blobs to the blobstore' do
        command.finalize('ignored.tgz')
        expect(blob_manager).to have_received(:upload_blob).with('blobs/foo/pending_blob_1.tar.gz')
        expect(blob_manager).to have_received(:upload_blob).with('src/bar/pending_blob_2.tar.gz')
      end

      it 'can do a dry run' do
        command.options[:dry_run] = true
        command.finalize('ignored.tgz')
        expect(tarball).to_not have_received(:replace_manifest)
        expect(version_index).to_not have_received(:add_version)
        expect(tarball).to_not have_received(:create_from_unpacked)
        expect(blob_manager).to_not have_received(:upload_blob)
      end

    end
  end
end
