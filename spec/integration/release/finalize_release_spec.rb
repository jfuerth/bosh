require 'securerandom'
require 'spec_helper'

describe 'finalize release', type: :integration do
  include Bosh::Spec::CreateReleaseOutputParsers
  with_reset_sandbox_before_each
  SHA1_REGEXP = /^[0-9a-f]{40}$/

  before { setup_test_release_dir }

  describe 'release finalization' do
    it 'can finalize an existing release' do
      Dir.chdir(ClientSandbox.test_release_dir) do
        out = bosh_runner.run_in_current_dir("finalize release #{spec_asset('dummy-release.tgz')}")
        expect(out).to match('Creating final release dummy/1 from dev release dummy/0.2-dev')
      end
    end

    it 'updates the .final_builds index for each job, package and license' do
      Dir.chdir(ClientSandbox.test_release_dir) do
        bosh_runner.run_in_current_dir("finalize release #{spec_asset('dummy-release.tgz')}")
        job_index = Psych.load_file(File.absolute_path('.final_builds/jobs/dummy/index.yml'))
        puts "JOB INDEX:", job_index
        expect(job_index).to include('builds')
        expect(job_index['builds']).to include('a2f501d07c3e96689185ee6ebe26c15d54d4849a')
        expect(job_index['builds']['a2f501d07c3e96689185ee6ebe26c15d54d4849a']).to include('version', 'blobstore_id', 'sha1')
      end
    end

    it 'updates the index' do

    end

    it 'cannot create a final release without the blobstore configured', no_reset: true do

    end

    it 'cannot create a final release without the blobstore secret configured', no_reset: true do
    end

    it 'allows creation of new final releases with the same content as the latest final release' do
    end

    it 'allows creation of new dev releases with the same content as the latest dev release' do
    end

    it 'allows creation of new final releases with the same content as a previous final release' do

    end

    it 'allows creation of new dev releases with the same content as a previous dev release' do
    end


    it 'allows creation of new final release without .gitignore files' do

    end

    context 'when no previous releases have been made' do
      it 'final release uploads the job & package blobs' do

      end

      it 'uses a provided --name' do

      end
    end

    context 'when previous release have been made' do
      it 'allows creation of a new dev release with a new name' do

      end

      it 'allows creation of a new final release with a new name' do

      end

      it 'allows creation of a new final release with a custom name & version' do

      end
    end

    it 'creates a new final release with a default version' do

    end
  end
end
