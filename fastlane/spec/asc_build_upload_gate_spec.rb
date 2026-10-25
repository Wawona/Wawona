# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/asc_build_upload_gate"

class AscBuildUploadGateSpec < Minitest::Test
  Upload = Struct.new(:id, :state, :uploaded_date, :created_date)
  Response = Struct.new(:uploads) do
    def all_pages
      [self]
    end

    def to_models
      uploads
    end
  end
  App = Struct.new(:id)

  class ConnectApi
    attr_reader :filters

    def initialize(upload_sequences)
      @upload_sequences = upload_sequences
      @filters = []
    end

    def get_build_uploads(app_id:, filter:, limit:, sort:)
      @filters << [app_id, filter, limit, sort]
      uploads = @upload_sequences.shift || []
      Response.new(uploads)
    end
  end

  def test_requires_a_new_matching_upload_to_complete
    old_upload = Upload.new("old", "COMPLETE", "2026-10-24", nil)
    pending = Upload.new("new", "PROCESSING", "2026-10-25", nil)
    complete = Upload.new("new", "COMPLETE", "2026-10-25", nil)
    api = ConnectApi.new([[old_upload], [old_upload], [pending], [complete]])
    time = 0
    gate = build_gate(api, clock: -> { time }, sleeper: ->(seconds) { time += seconds })

    baseline = gate.baseline_ids
    result = gate.wait_for_complete!(baseline)

    assert_equal "new", result.id
    assert_equal 4, api.filters.length
    assert api.filters.all? { |row| row[1] == {
      cfBundleShortVersionString: "26.10.25",
      cfBundleVersion: "123",
      platform: "IOS"
    } }
    assert api.filters.all? { |row| row[0] == "app-id" && row[2] == 200 && row[3] == "-uploadedDate" }
  end

  def test_fails_on_apple_rejection
    rejected = Upload.new("bad", "FAILED", "2026-10-25", nil)
    api = ConnectApi.new([[], [rejected]])
    gate = build_gate(api, clock: -> { 0 })

    error = assert_raises(RuntimeError) { gate.wait_for_complete!([]) }
    assert_includes error.message, "build upload bad is FAILED"
  end

  def test_fails_when_apple_never_reports_a_new_upload
    api = ConnectApi.new([[], []])
    time = 0
    gate = build_gate(api, timeout_seconds: 2, clock: -> { time }, sleeper: ->(seconds) { time += seconds })

    error = assert_raises(RuntimeError) { gate.wait_for_complete!([]) }
    assert_includes error.message, "within 2s"
  end

  private

  def build_gate(api, timeout_seconds: 10, clock: -> { 0 }, sleeper: ->(_seconds) {})
    Wawona::AscBuildUploadGate.new(
      connect_api: api,
      app: App.new("app-id"),
      version: "26.10.25",
      build_number: "123",
      platform: "ios",
      timeout_seconds: timeout_seconds,
      poll_interval_seconds: 1,
      clock: clock,
      sleeper: sleeper
    )
  end
end
