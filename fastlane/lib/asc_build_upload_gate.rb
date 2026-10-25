# frozen_string_literal: true

module Wawona
  # Fails a release lane unless App Store Connect finishes processing the exact
  # version, build, and platform submitted by this lane.
  class AscBuildUploadGate
    PLATFORM = {
      "ios" => "IOS",
      "appletvos" => "TV_OS",
      "xros" => "VISION_OS"
    }.freeze

    def initialize(connect_api:, app:, version:, build_number:, platform:,
                   timeout_seconds:, poll_interval_seconds: 30,
                   logger: ->(_message) {}, sleeper: ->(seconds) { Kernel.sleep(seconds) },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @connect_api = connect_api
      @app = app
      @version = version
      @build_number = build_number
      @platform = PLATFORM.fetch(platform) do
        raise ArgumentError, "Unsupported App Store Connect platform: #{platform}"
      end
      @timeout_seconds = timeout_seconds
      @poll_interval_seconds = poll_interval_seconds
      raise ArgumentError, "timeout_seconds must be positive" unless @timeout_seconds.positive?
      raise ArgumentError, "poll_interval_seconds must be positive" unless @poll_interval_seconds.positive?

      @logger = logger
      @sleeper = sleeper
      @clock = clock
    end

    def baseline_ids
      fetch_uploads.map(&:id)
    end

    def wait_for_complete!(baseline_ids)
      deadline = @clock.call + @timeout_seconds

      loop do
        upload = fetch_uploads
          .reject { |record| baseline_ids.include?(record.id) }
          .max_by { |record| record.uploaded_date || record.created_date || "" }

        if upload
          case upload.state
          when "COMPLETE"
            @logger.call(
              "App Store Connect accepted #{@version} (#{@build_number}, #{@platform}); " \
              "build upload #{upload.id} is COMPLETE"
            )
            return upload
          when "FAILED"
            raise "App Store Connect rejected #{@version} (#{@build_number}, #{@platform}); " \
                  "build upload #{upload.id} is FAILED. Open this upload in App Store Connect " \
                  "to inspect Apple's diagnostics."
          else
            @logger.call(
              "App Store Connect build upload #{upload.id} is " \
              "#{upload.state || 'pending'}; waiting for COMPLETE"
            )
          end
        else
          @logger.call(
            "Waiting for App Store Connect upload record for #{@version} " \
            "(#{@build_number}, #{@platform})"
          )
        end

        remaining = deadline - @clock.call
        if remaining <= 0
          raise "App Store Connect did not report a COMPLETE build upload for #{@version} " \
                "(#{@build_number}, #{@platform}) within #{@timeout_seconds}s"
        end
        @sleeper.call([@poll_interval_seconds, remaining].min)
      end
    end

    private

    def fetch_uploads
      filter = {
        cfBundleShortVersionString: @version,
        cfBundleVersion: @build_number,
        platform: @platform
      }
      @connect_api.get_build_uploads(
        app_id: @app.id,
        filter: filter,
        limit: 200,
        sort: "-uploadedDate"
      ).all_pages.flat_map(&:to_models)
    end
  end
end
