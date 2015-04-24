require File.expand_path(File.dirname(__FILE__) + '/../../release_print_helper.rb')
module Bosh::Cli::Command
  module Release
    class FinalizeRelease < Base
      include ReleasePrintHelper
      include Bosh::Cli::DependencyHelper

      # bosh finalize release
      usage 'finalize release'
      desc 'Create final release from dev release tarball (assumes current directory to be a release repository)'
      option '--dry-run', 'stop before writing release manifest'
      option '--name NAME', 'specify a custom release name'
      option '--version VERSION', 'specify a custom version number (ex: 1.0.0 or 1.0-beta.2+dev.10)'

      def finalize(tarball_path)
        options[:final] = true
        check_if_release_dir
        tarball = Bosh::Cli::ReleaseTarball.new(tarball_path)
        err("Cannot find release tarball #{tarball_path}") if !tarball.exists?

        err("#{tarball_path} is not a valid release tarball") if !tarball.valid?(:print_release_info => false)

        manifest = Psych.load(tarball.manifest)

        dev_release_name = manifest["name"]
        dev_release_ver = manifest["version"]

        final_release_name = options[:name] || dev_release_name
        @release_index = Bosh::Cli::Versions::VersionsIndex.new(File.join('releases', final_release_name))
        @release_storage = Bosh::Cli::Versions::LocalArtifactStorage.new(@release_index.storage_dir)

        if options[:version] && @release_index.version_strings.include?(options[:version])
          raise Bosh::Cli::ReleaseVersionError.new('Release version already exists')
        end

        latest_final_version = Bosh::Cli::Versions::ReleaseVersionsIndex.new(@release_index).latest_version
        latest_final_version ||= Bosh::Common::Version::ReleaseVersion.parse('0')
        latest_final_version = latest_final_version.increment_release

        final_release_ver = options[:version] || latest_final_version.to_s

        blob_manager.sync
        if blob_manager.dirty?
          blob_manager.print_status
          err("Please use '--force' or upload new blobs")
        end

        @progress_renderer = Bosh::Cli::InteractiveProgressRenderer.new

        if !options[:dry_run] then
          release.blobstore # prime & validate blobstore config

          manifest["version"] = final_release_ver
          manifest["name"] = final_release_name

          tarball.replace_manifest(manifest)

          FileUtils.mkdir_p("releases/#{final_release_name}")
          release_manifest_file = File.open("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml", "w")
          release_manifest_file.puts(tarball.manifest)

          @release_index.add_version(SecureRandom.uuid, "version" => final_release_ver)

          final_release_tarball_path = File.absolute_path("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.tgz")
          tarball.create_from_unpacked(final_release_tarball_path)

          # upload all packages & jobs to the blobstore
          manifest['packages'].each do |package|
            upload_to_blobstore(package, 'packages', tarball.package_tarball_path(package['name']))
          end

          manifest['jobs'].each do |job|
            upload_to_blobstore(job, 'jobs', tarball.job_tarball_path(job['name']))
          end

          if manifest['license']
            license_metadata = manifest['license'].clone
            license_metadata['name'] = 'license'
            upload_to_blobstore(license_metadata, '', tarball.license_tarball_path)
          end

          nl
          say("Creating final release #{final_release_name}/#{final_release_ver} from dev release #{dev_release_name}/#{dev_release_ver}")

          release.latest_release_filename = File.absolute_path("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml")
          release.save_config

          header('Release summary')
          show_summary(tarball)
          nl

          say("Release name: #{final_release_name.make_green}")
          say("Release version: #{final_release_ver.to_s.make_green}")
          say("Release manifest: #{release.latest_release_filename.make_green}")
          say("Release tarball (#{pretty_size(final_release_tarball_path)}): " + final_release_tarball_path.make_green)
        end
      end

      def upload_to_blobstore(artifact, plural_type, artifact_path)
        err("Cannot find artifact complete information, please upgrade tarball to newer version") if !artifact['fingerprint']

        final_builds_dir = File.join('.final_builds', plural_type, artifact['name']).to_s
        FileUtils.mkdir_p(final_builds_dir)
        final_builds_index = Bosh::Cli::Versions::VersionsIndex.new(final_builds_dir)

        return artifact if final_builds_index[artifact['fingerprint']]

        @progress_renderer.start(artifact['name'], "uploading...")
        blobstore_id = nil
        File.open(artifact_path, 'r') do |f|
          blobstore_id = @release.blobstore.create(f)
        end

        final_builds_index.add_version(artifact['fingerprint'], {
            'version' => artifact['version'],
            'sha1' => artifact['sha1'],
            'blobstore_id' => blobstore_id
          })
        @progress_renderer.finish(artifact['name'], "uploaded")
      end
    end
  end
end
