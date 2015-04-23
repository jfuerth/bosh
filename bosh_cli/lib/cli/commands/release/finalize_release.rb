module Bosh::Cli::Command
  module Release
    class FinalizeRelease < Base
      include Bosh::Cli::DependencyHelper

      # bosh finalize release
      usage 'finalize release'
      desc 'Create final release from dev release tarball (assumes current directory to be a release repository)'
      option '--dry-run', 'stop before writing release manifest'
      option '--name NAME', 'specify a custom release name'
      option '--version VERSION', 'specify a custom version number (ex: 1.0.0 or 1.0-beta.2+dev.10)'

      def finalize(tarball_path)
        check_if_release_dir
        tarball = Bosh::Cli::ReleaseTarball.new(tarball_path)
        raise Bosh::Cli::CliError.new("Cannot find release tarball #{tarball_path}") if !tarball.exists?

        tarball.perform_validation

        manifest = Psych.load(tarball.manifest)
        # packages:
        # - name: go-lang-1.3
        #   version: 6279e334a5735c628b1e09b0b376ffd62a381e97
        #   fingerprint: 6279e334a5735c628b1e09b0b376ffd62a381e97
        #   sha1: ac93ae96ede786dc383deebc6d1261da0e5c3a61
        #   dependencies: []
        # - name: go-lang-1.4.2
        #   version: b69852dec2121ca951d83deef79d3160ca6d270c
        #   fingerprint: b69852dec2121ca951d83deef79d3160ca6d270c
        #   sha1: b02355dfffd132ed7f28b7de3495e36857ebb215
        #   dependencies: []
        # - name: hello-go
        #   version: ad9a6cec10b1d975f523d16d0ed49e812036ed23
        #   fingerprint: ad9a6cec10b1d975f523d16d0ed49e812036ed23
        #   sha1: 65565f741c41c676ac6a60ab8697c38ddaabdfc0
        #   dependencies:
        #     - go-lang-1.4.2
        #   jobs:
        #     - name: hello-go
        #   version: 02a50fae60301efcadfec0f9f9b21801af7b2421
        #   fingerprint: 02a50fae60301efcadfec0f9f9b21801af7b2421
        #   sha1: 05d6d5dfd861cbdb1b48aaea094bd433b418ce7c
        # commit_hash: '00000000'
        # uncommitted_changes: false
        # name: hello-go
        # version: '2'
        dev_release_name = manifest["name"]
        dev_release_ver = manifest["version"]

        final_release_name = options[:name] || dev_release_name
        @final_index = Bosh::Cli::Versions::VersionsIndex.new(File.join('releases', final_release_name))
        @release_storage = Bosh::Cli::Versions::LocalArtifactStorage.new(@final_index.storage_dir)

        latest_final_version = Bosh::Cli::Versions::ReleaseVersionsIndex.new(@final_index).latest_version
        latest_final_version ||= Bosh::Common::Version::ReleaseVersion.parse('0')
        latest_final_version = latest_final_version.increment_release

        final_release_ver = options[:version] || latest_final_version.to_s

        if @release_storage.has_file?("#{final_release_name}-#{final_release_ver}.yml")
          raise Bosh::Cli::ReleaseVersionError.new('Release version already exists')
        end

        blob_manager.sync
        if blob_manager.dirty?
          blob_manager.print_status
          err("Please use '--force' or upload new blobs")
        end

        if !options[:dry_run] then
          say("Creating final release #{final_release_name}/#{final_release_ver} from dev release #{dev_release_name}/#{dev_release_ver}")

          manifest["version"] = final_release_ver
          manifest["name"] = final_release_name

          tarball.replace_manifest(manifest)

          FileUtils.mkdir_p("releases/#{final_release_name}")
          release_manifest_file = File.open("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml", "w")
          release_manifest_file.puts(tarball.manifest)

          @final_index.add_version(SecureRandom.uuid, "version" => final_release_ver)

          tarball.create_from_unpacked("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.tgz")

          # upload all packages & jobs to the blobstore
          manifest['packages'].each do |package|
            upload_to_blobstore(package, 'packages', tarball.package_tarball_path(package['name']))
          end

          manifest['jobs'].each do |job|
            upload_to_blobstore(job, 'jobs', tarball.job_tarball_path(job['name']))
          end

          # update each package in .final_builds/packages with blobstore_id
          # update license info in .final_builds/license

          release.latest_release_filename = "releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml"
          release.save_config
        end
      end

      def upload_to_blobstore(artifact, plural_type, artifact_path)

        err("Cannot find artifact complete information, please upgrade tarball to newer version") if !artifact['fingerprint']

        final_builds_dir = File.join('.final_builds', plural_type, artifact['name']).to_s
        FileUtils.mkdir_p(final_builds_dir)
        final_builds_index = Bosh::Cli::Versions::VersionsIndex.new(final_builds_dir)

        return artifact if final_builds_index[artifact['fingerprint']]

        blobstore_id = nil
        File.open(artifact_path, 'r') do |f|
          blobstore_id = @release.blobstore.create(f)
        end

        final_builds_index.add_version(artifact['fingerprint'], {
            'version' => artifact['version'],
            'sha1' => artifact['sha1'],
            'blobstore_id' => blobstore_id
          })
      end
    end
  end
end
