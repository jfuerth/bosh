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

        raise Bosh::Cli::CliError.new("Release tarball already has final version #{tarball.version}") unless tarball.version.include? "dev"

        manifest = Psych.load(tarball.manifest)
        # manifest = {
        #     "name" => "appcloud",
        #     "version" => "8.1+dev.3",
        #     "packages" => [
        #         {"name" => "stuff", "version" => "0.1.17",
        #          "sha1" => "6bbd4a12e3a59e10b96ecb9aac3d73ec4f819783"},
        #         {"name" => "mutator", "version" => "2.99.7",
        #          "sha1" => "86bd8b15562cde007f030a303fa64779af5fa4e7"}
        #     ],
        #     "jobs" => [
        #         {"name" => "cacher",
        #          "version" => 1,
        #          "sha1" => "be1d5996db911110b6c8935500804456134a60af"},
        #         {"name" => "cleaner",
        #          "version" => 2,
        #          "sha1" => "db0148e48e96ed11065432df22909c8c9bb80bc5"},
        #         {"name" => "sweeper",
        #          "version" => 24,
        #          "sha1" => "2f5ee446056c8b835b16c6917bee2ac234d679ce"}
        #     ]
        # }

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

        if !options[:dry_run] then
          say("Creating final release #{final_release_name}/#{final_release_ver} from dev release #{dev_release_name}/#{dev_release_ver}")
          nl
          say("Checking for blobs that need to be uploaded")
          blob_manager.print_status
          blob_manager.blobs_to_upload.each do |blob|
            say("Uploading #{blob}")
            blob_manager.upload_blob(blob)
          end

          manifest["version"] = final_release_ver
          manifest["name"] = final_release_name

          tarball.replace_manifest(manifest)

          FileUtils.mkdir_p("releases/#{final_release_name}")
          release_manifest_file = File.open("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml", "w")
          release_manifest_file.puts(tarball.manifest)

          @final_index.add_version(SecureRandom.uuid, "version" => final_release_ver)

          tarball.create_from_unpacked("releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.tgz")

          release.latest_release_filename = "releases/#{final_release_name}/#{final_release_name}-#{final_release_ver}.yml"
          release.save_config
        end
      end
    end
  end
end
