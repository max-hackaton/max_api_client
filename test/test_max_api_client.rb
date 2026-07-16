# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require "tempfile"

# rubocop:disable Metrics/ClassLength
class TestMaxApiClient < Minitest::Test
  def build_api(responses = [], &block)
    queue = responses.dup
    requests = []
    adapter = lambda do |request|
      requests << request
      if block
        block.call(request)
      else
        queue.shift || { status: 200, data: {} }
      end
    end

    [MaxApiClient::Api.new(token: "test-token", adapter:), requests]
  end

  def test_that_it_has_a_version_number
    refute_nil ::MaxApiClient::VERSION
  end

  def test_it_exposes_error_class
    assert_equal StandardError, MaxApiClient::Error.superclass
  end

  def test_default_tls_store_trusts_bundled_ministry_root
    certificate = OpenSSL::X509::Certificate.new(File.binread(MaxApiClient::Client::DEFAULT_CA_FILE))
    store = MaxApiClient::CertificateStore.build(ca_file: MaxApiClient::Client::DEFAULT_CA_FILE)
    verified = store.verify(certificate)

    assert verified
    assert_equal(
      "D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31",
      OpenSSL::Digest::SHA256.hexdigest(certificate.to_der).scan(/../).join(":").upcase
    )
  end

  def test_ssl_verification_is_enabled_by_default
    client = MaxApiClient::Client.new(token: "test-token")
    http = client.send(:configured_http, URI("https://example.test"), open_timeout: nil, read_timeout: nil)

    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    refute_nil http.cert_store
  end

  def test_ssl_verification_can_be_disabled
    api = MaxApiClient::Api.new(token: "test-token", verify_ssl: false)
    http = api.client.send(:configured_http, URI("https://example.test"), open_timeout: nil, read_timeout: nil)

    refute api.client.verify_ssl
    assert_equal OpenSSL::SSL::VERIFY_NONE, http.verify_mode
    assert_nil http.cert_store
  end

  def test_api_exposes_ts_parity_methods
    api, = build_api

    %i[
      get_my_info edit_my_info set_my_commands delete_my_commands
      get_all_chats get_chat get_chat_by_link edit_chat_info
      get_chat_membership get_chat_admins add_chat_members get_chat_members remove_chat_member
      get_pinned_message pin_message unpin_message send_action leave_chat
      send_message_to_chat send_message_to_user get_messages get_message edit_message delete_message
      answer_on_callback get_subscriptions subscribe unsubscribe poll_updates
      upload_image upload_video upload_audio upload_file
    ].each do |method_name|
      assert_respond_to api, method_name
    end
  end

  def test_get_subscriptions_uses_subscriptions_endpoint
    api, requests = build_api([{ status: 200, data: { "subscriptions" => [] } }])

    api.get_subscriptions

    assert_equal :get, requests.first[:method]
    assert_equal URI("https://platform-api2.max.ru/subscriptions"), requests.first[:url]
  end

  def test_subscribe_posts_subscription_body
    api, requests = build_api([{ status: 200, data: { "url" => "https://example.com/webhook" } }])

    api.subscribe("https://example.com/webhook", update_types: %w[message_created bot_started], secret: "secret")

    assert_equal :post, requests.first[:method]
    assert_equal URI("https://platform-api2.max.ru/subscriptions"), requests.first[:url]
    assert_equal(
      { url: "https://example.com/webhook", update_types: %w[message_created bot_started], secret: "secret" },
      requests.first[:body]
    )
  end

  def test_unsubscribe_deletes_subscription_by_url
    api, requests = build_api([{ status: 200, data: {} }])

    api.unsubscribe("https://example.com/webhook")

    assert_equal :delete, requests.first[:method]
    assert_equal URI("https://platform-api2.max.ru/subscriptions?url=https%3A%2F%2Fexample.com%2Fwebhook"),
                 requests.first[:url]
  end

  def test_send_message_to_chat_uses_messages_endpoint
    api, requests = build_api([{ status: 200, data: { "message" => { "body" => { "text" => "Hello" } } } }])

    response = api.send_message_to_chat(123, "Hello", format: "markdown")

    assert_equal "Hello", response.dig("body", "text")
    assert_equal :post, requests.first[:method]
    assert_equal URI("https://platform-api2.max.ru/messages?chat_id=123"), requests.first[:url]
    assert_equal({ text: "Hello", format: "markdown" }, requests.first[:body])
  end

  # rubocop:disable Metrics/AbcSize
  def test_poll_updates_tracks_marker_between_requests
    api, requests = build_api(poll_updates_responses)
    updates = poll_updates_once(api)

    assert_equal [{ "update_type" => "message_created" }], updates
    assert_equal URI("https://platform-api2.max.ru/updates?types=message_created&timeout=20"), requests[0][:url]
    assert_equal URI("https://platform-api2.max.ru/updates?types=message_created&marker=10&timeout=20"),
                 requests[1][:url]
    assert_equal 25, requests[0][:read_timeout]
    assert_equal 25, requests[1][:read_timeout]
  end
  # rubocop:enable Metrics/AbcSize

  def test_raw_get_updates_remains_available
    api, requests = build_api([{ status: 200, data: { "updates" => [] } }])

    api.raw.subscriptions.get_updates(types: "message_created,bot_started", marker: 42)

    assert_equal URI("https://platform-api2.max.ru/updates?types=message_created%2Cbot_started&marker=42"),
                 requests.first[:url]
  end

  def test_get_chat_members_joins_user_ids
    api, requests = build_api([{ status: 200, data: { "members" => [] } }])

    api.get_chat_members(10, user_ids: [1, 2, 3], count: 50)

    assert_equal URI("https://platform-api2.max.ru/chats/10/members?user_ids=1%2C2%2C3&count=50"), requests.first[:url]
  end

  def test_messages_send_retries_attachment_not_ready
    api, requests = build_api([
                                { status: 400,
                                  data: { "code" => "attachment.not.ready", "message" => "Attachment not ready" } },
                                { status: 200, data: { "message" => { "id" => "mid" } } }
                              ])

    response = api.send_message_to_chat(1, "hello")

    assert_equal "mid", response["id"]
    assert_equal 2, requests.size
  end

  def test_remove_chat_member_preserves_false_block_flag
    api, requests = build_api([{ status: 200, data: {} }])

    api.remove_chat_member(10, 42, block: false)

    assert_equal({ user_id: 42, block: false }, requests.first[:body])
  end

  def test_pin_message_preserves_false_notify_flag
    api, requests = build_api([{ status: 200, data: {} }])

    api.pin_message(10, "mid", notify: false)

    assert_equal({ message_id: "mid", notify: false }, requests.first[:body])
  end

  def test_upload_image_from_url_returns_attachment_without_network_upload
    api, requests = build_api

    attachment = api.upload_image(url: "https://example.com/image.png")

    assert_instance_of MaxApiClient::ImageAttachment, attachment
    assert_equal({ type: "image", payload: { url: "https://example.com/image.png" } }, attachment.to_h)
    assert_empty requests
  end

  # rubocop:disable Metrics/AbcSize
  def test_upload_file_uses_uploads_endpoint_and_returns_attachment
    Tempfile.create(["max-api-client", ".txt"]) do |file|
      file.write("payload")
      file.flush

      api, requests = build_api([
                                  { status: 200,
                                    data: { "url" => "https://upload.example.test/files", "token" => "upload-token" } },
                                  { status: 200, data: "" }
                                ])

      attachment = api.upload_file(source: file.path)

      assert_instance_of MaxApiClient::FileAttachment, attachment
      assert_equal({ type: "file", payload: { token: "upload-token" } }, attachment.to_h)
      assert_equal URI("https://platform-api2.max.ru/uploads?type=file"), requests[0][:url]
      assert_equal URI("https://upload.example.test/files"), requests[1][:url]
      assert_equal :post, requests[1][:method]
      assert_equal "payload", requests[1][:raw_body]
    end
  end
  # rubocop:enable Metrics/AbcSize

  def test_upload_file_passes_timeout_to_upload_request
    Tempfile.create(["max-api-client", ".txt"]) do |file|
      file.write("payload")
      file.flush

      api, requests = build_api([
                                  { status: 200,
                                    data: { "url" => "https://upload.example.test/files", "token" => "upload-token" } },
                                  { status: 200, data: "" }
                                ])

      api.upload_file(source: file.path, timeout: 7)

      assert_equal 7, requests[1][:open_timeout]
      assert_equal 7, requests[1][:read_timeout]
    end
  end

  def test_client_logs_request_and_response_with_instance_logger
    output = StringIO.new
    logger = Logger.new(output)
    logger.level = Logger::DEBUG
    client = MaxApiClient::Client.new(
      token: "secret-token",
      logger:,
      adapter: lambda { |_request|
        { status: 200, data: { "ok" => true }, headers: { "content-type" => ["application/json"] } }
      }
    )

    client.call(method: :get, path: "/me")

    logs = output.string

    assert_includes logs, "max_api_client.request"
    assert_includes logs, "max_api_client.response"
    assert_includes logs, "[FILTERED]"
    refute_includes logs, "secret-token"
  end

  private

  def poll_updates_responses
    [
      { status: 200, data: { "updates" => [], "marker" => 10 } },
      { status: 200, data: { "updates" => [{ "update_type" => "message_created" }], "marker" => 11 } }
    ]
  end

  def poll_updates_once(api)
    poller = MaxApiClient::Polling.new(api, types: %w[message_created], timeout: 20)
    updates = []

    poller.each do |update|
      updates << update
      poller.stop
    end

    updates
  end
end
# rubocop:enable Metrics/ClassLength
