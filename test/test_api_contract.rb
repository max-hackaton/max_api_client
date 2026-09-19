# frozen_string_literal: true

require "test_helper"
require "stringio"

# Regression tests for the documented MAX Bot API HTTP contract.
# rubocop:disable Metrics/ClassLength
class TestApiContract < Minitest::Test
  def test_set_my_commands_uses_commands_endpoint
    commands = [{ name: "start", description: "Start the bot" }]
    api, requests = build_api({ "commands" => commands })

    response = api.set_my_commands(commands)

    assert_request requests.first, :patch, "/me/commands", body: { commands: }
    assert_equal({ "commands" => commands }, response)
  end

  def test_raw_edit_my_commands_uses_commands_endpoint
    api, requests = build_api

    api.raw.bots.edit_my_commands(commands: [])

    assert_request requests.first, :patch, "/me/commands", body: { commands: [] }
  end

  def test_delete_my_commands_sends_empty_array
    api, requests = build_api

    api.delete_my_commands

    assert_request requests.first, :patch, "/me/commands", body: { commands: [] }
  end

  def test_legacy_edit_my_info_routes_commands_to_supported_endpoint
    api, requests = build_api

    api.edit_my_info(commands: [])

    assert_request requests.first, :patch, "/me/commands", body: { commands: [] }
  end

  def test_legacy_profile_edit_rejects_unsupported_fields_before_request
    api, requests = build_api

    assert_raises(ArgumentError) { api.edit_my_info(name: "New name") }
    assert_empty requests
  end

  def test_legacy_profile_edit_does_not_silently_drop_fields
    api, requests = build_api

    assert_raises(ArgumentError) { api.raw.bots.edit_my_info(commands: [], name: "New name") }
    assert_empty requests
  end

  def test_get_message_returns_message_from_documented_endpoint
    message = { "body" => { "mid" => "mid.123" } }
    api, requests = build_api(message)

    response = api.get_message("mid.123")

    assert_request requests.first, :get, "/messages/mid.123"
    assert_equal message, response
  end

  def test_raw_get_message_escapes_identifier_as_one_path_segment
    api, requests = build_api

    api.raw.messages.get_by_id(message_id: "mid/a+b?c#d")

    assert_request requests.first, :get, "/messages/mid%2Fa%2Bb%3Fc%23d"
  end

  def test_get_message_preserves_api_error_handling
    api, = build_api({ "code" => "message.not.found", "message" => "Not found" }, status: 404)

    error = assert_raises(MaxApiClient::ApiError) { api.get_message("missing") }

    assert_equal 404, error.status
    assert_equal "message.not.found", error.code
  end

  def test_remove_chat_member_omits_unset_block_parameter
    api, requests = build_api

    api.remove_chat_member(-10, 42)

    assert_request requests.first, :delete, "/chats/-10/members?user_id=42"
  end

  def test_raw_remove_chat_member_uses_query_for_block_true
    api, requests = build_api

    api.raw.chats.remove_chat_member(chat_id: 10, user_id: 42, block: true)

    assert_request requests.first, :delete, "/chats/10/members?user_id=42&block=true"
  end

  def test_send_message_preserves_false_preview_and_notify_flags
    api, requests = build_api({ "message" => {} })

    api.send_message_to_chat(10, "Hello", disable_link_preview: false, notify: false)

    assert_request requests.first, :post, "/messages?chat_id=10&disable_link_preview=false",
                   body: { text: "Hello", notify: false }
  end

  def test_raw_messages_serialize_arrays_as_csv_without_mutating_input
    api, requests = build_api
    message_ids = %w[mid.1 mid.2].freeze

    api.raw.messages.get(message_ids:)

    assert_request requests.first, :get, "/messages?message_ids=mid.1%2Cmid.2"
    assert_equal %w[mid.1 mid.2], message_ids
  end

  def test_raw_chat_members_serialize_user_ids_as_csv
    api, requests = build_api

    api.raw.chats.get_chat_members(chat_id: 10, user_ids: [1, 2], count: 20)

    assert_request requests.first, :get, "/chats/10/members?user_ids=1%2C2&count=20"
  end

  def test_raw_updates_serialize_types_as_csv
    api, requests = build_api

    api.raw.subscriptions.get_updates(types: %w[message_created bot_started], marker: 0, read_timeout: 30)

    assert_request requests.first, :get, "/updates?types=message_created%2Cbot_started&marker=0"
    assert_equal 30, requests.first[:read_timeout]
  end

  def test_query_serialization_keeps_existing_query_and_omits_only_nil
    api, requests = build_api

    api.client.call(method: :get, path: "messages?existing=a%2Bb", query: { flag: false, marker: 0, absent: nil })

    assert_request requests.first, :get, "/messages?existing=a%2Bb&flag=false&marker=0"
  end

  def test_get_messages_accepts_message_ids_without_chat_id
    api, requests = build_api({ "messages" => [] })

    response = api.get_messages(message_ids: %w[mid.1 mid.2])

    assert_request requests.first, :get, "/messages?message_ids=mid.1%2Cmid.2"
    assert_equal({ "messages" => [] }, response)
  end

  def test_get_messages_preserves_positional_chat_id_and_pagination
    api, requests = build_api

    api.get_messages(-10, count: 25, from: 0, to: 100)

    assert_request requests.first, :get, "/messages?chat_id=-10&count=25&from=0&to=100"
  end

  def test_get_messages_accepts_keyword_chat_id
    api, requests = build_api

    api.get_messages(chat_id: 10)

    assert_request requests.first, :get, "/messages?chat_id=10"
  end

  def test_get_messages_preserves_already_serialized_ids
    api, requests = build_api

    api.get_messages(nil, message_ids: "mid.1,mid.2")

    assert_request requests.first, :get, "/messages?message_ids=mid.1%2Cmid.2"
  end

  def test_upload_image_preserves_token_from_parsed_json
    attachment, requests = upload_image(JSON.parse('{"token":"image-token"}'))

    assert_equal({ type: "image", payload: { token: "image-token" } }, attachment.to_h)
    assert_equal "image", requests.first[:query][:type]
    assert_match(/multipart\/form-data/, requests.last[:headers]["Content-Type"])
  end

  def test_upload_image_preserves_photos_from_parsed_json
    data = JSON.parse('{"photos":{"photo-id":{"token":"image-token"}}}')

    attachment, = upload_image(data)

    assert_equal({ type: "image", payload: { photos: data.fetch("photos") } }, attachment.to_h)
  end

  def test_upload_image_preserves_symbol_keyed_adapter_responses
    photos = { "photo-id" => { token: "image-token" } }

    attachment, = upload_image({ photos: })

    assert_equal({ type: "image", payload: { photos: } }, attachment.to_h)
  end

  def test_commands_request_builds_authenticated_json_http_request
    api, requests = build_api
    api.delete_my_commands
    request = requests.first

    http_request = api.client.send(:build_http_request, request, request.fetch(:url))

    assert_equal "PATCH", http_request.method
    assert_equal "/me/commands", http_request.path
    assert_equal "test-token", http_request["Authorization"]
    assert_equal "application/json", http_request["Content-Type"]
    assert_equal({ "commands" => [] }, JSON.parse(http_request.body))
  end

  def test_remove_member_builds_bodyless_http_request
    api, requests = build_api
    api.remove_chat_member(10, 42, block: false)
    request = requests.first

    http_request = api.client.send(:build_http_request, request, request.fetch(:url))

    assert_equal "DELETE", http_request.method
    assert_equal "/chats/10/members?user_id=42&block=false", http_request.path
    assert_nil http_request.body
    assert_nil http_request["Content-Type"]
  end

  private

  def build_api(data = {}, status: 200)
    requests = []
    adapter = lambda do |request|
      requests << request
      { status:, data: }
    end
    [MaxApiClient::Api.new(token: "test-token", adapter:), requests]
  end

  def assert_request(request, method, path, body: nil)
    assert_equal method, request.fetch(:method)
    assert_equal URI("https://platform-api2.max.ru#{path}"), request.fetch(:url)
    if body.nil?
      assert_nil request[:body]
    else
      assert_equal body, request[:body]
    end
  end

  def upload_image(data)
    requests = []
    adapter = lambda do |request|
      requests << request
      response = requests.size == 1 ? { "url" => "https://upload.example.test/images" } : data
      { status: 200, data: response }
    end
    api = MaxApiClient::Api.new(token: "test-token", adapter:)
    attachment = api.upload_image(source: StringIO.new("image-bytes"), filename: "image.png")
    [attachment, requests]
  end
end
# rubocop:enable Metrics/ClassLength
