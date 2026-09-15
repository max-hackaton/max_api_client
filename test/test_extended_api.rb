# frozen_string_literal: true

require "test_helper"

# Contract checks use an adapter and real Net::HTTP request construction, never MAX credentials.
# rubocop:disable Metrics/ClassLength
class TestExtendedApi < Minitest::Test
  def test_new_raw_groups_are_memoized
    api, = build_api

    assert_instance_of MaxApiClient::VideosApi, api.raw.videos
    assert_instance_of MaxApiClient::CommentsApi, api.raw.comments
    assert_same api.raw.videos, api.raw.videos
    assert_same api.raw.comments, api.raw.comments
  end

  def test_set_chat_admins_sends_json_and_preserves_zero_marker
    admins = [{ user_id: 42, permissions: %w[read_all_messages write].freeze, alias: "Editor" }.freeze].freeze
    result = { "success" => true }
    api, requests = build_api(result)

    assert_equal result, api.set_chat_admins(-10, admins, marker: 0)
    assert_request requests.first, :post, "/chats/-10/members/admins", body: { admins:, marker: 0 }
  end

  def test_raw_set_chat_admins_omits_unset_marker
    api, requests = build_api

    api.raw.chats.set_chat_admins(chat_id: 10, admins: [{ "user_id" => 42, "permissions" => ["write"] }])

    assert_request requests.first, :post, "/chats/10/members/admins",
                   body: { admins: [{ "user_id" => 42, "permissions" => ["write"] }] }
  end

  def test_admin_update_does_not_promote_unsuccessful_result_to_success
    result = { "success" => false, "message" => "Not allowed" }
    api, = build_api(result)

    assert_equal result, api.set_chat_admins(10, [])
  end

  def test_remove_chat_admin_is_bodyless_and_does_not_remove_membership
    api, requests = build_api({ "success" => true })

    api.remove_chat_admin(-10, 42)

    assert_request requests.first, :delete, "/chats/-10/members/admins/42"
  end

  def test_raw_remove_chat_admin
    api, requests = build_api

    api.raw.chats.remove_chat_admin(chat_id: 10, user_id: 42)

    assert_request requests.first, :delete, "/chats/10/members/admins/42"
  end

  def test_get_video_returns_metadata_including_unavailable_urls
    data = { "token" => "video-token", "urls" => nil, "thumbnail" => nil, "width" => 640, "duration" => 3 }
    api, requests = build_api(data)

    assert_equal data, api.get_video("video-token")
    assert_request requests.first, :get, "/videos/video-token"
  end

  def test_raw_video_token_is_escaped_as_one_path_segment
    api, requests = build_api

    api.raw.videos.get_by_token(video_token: "token/with+?query#fragment")

    assert_request requests.first, :get, "/videos/token%2Fwith%2B%3Fquery%23fragment"
  end

  def test_get_comments_preserves_result_and_time_filters
    result = { "messages" => [], "marker" => 9 }
    api, requests = build_api(result)

    assert_equal result, api.get_comments("mid.post", after: 0, before: 1000, count: 25)
    assert_request requests.first, :get, "/messages/mid.post/comments?after=0&before=1000&count=25"
  end

  def test_raw_comments_serialize_frozen_ids_as_csv
    api, requests = build_api
    ids = %w[mid.first mid.second].freeze

    api.raw.comments.get(message_id: "mid.post", comment_ids: ids, count: nil)

    assert_request requests.first, :get, "/messages/mid.post/comments?comment_ids=mid.first%2Cmid.second"
    assert_equal %w[mid.first mid.second], ids
  end

  def test_high_level_comments_accept_serialized_ids
    api, requests = build_api

    api.get_comments("mid.post", comment_ids: "mid.first,mid.second")

    assert_request requests.first, :get, "/messages/mid.post/comments?comment_ids=mid.first%2Cmid.second"
  end

  def test_get_comment_returns_comment_without_unwrapping
    result = { "body" => { "mid" => "mid.comment", "text" => "Hello" } }
    api, requests = build_api(result)

    assert_equal result, api.get_comment("mid.post", "mid.comment")
    assert_request requests.first, :get, "/messages/mid.post/comments/mid.comment"
  end

  def test_raw_get_comment_escapes_both_path_identifiers
    api, requests = build_api

    api.raw.comments.get_by_id(message_id: "post/one", comment_id: "comment?two")

    assert_request requests.first, :get, "/messages/post%2Fone/comments/comment%3Ftwo"
  end

  def test_send_comment_unwraps_message_like_send_message
    comment = { "body" => { "mid" => "mid.comment", "text" => "Hello" } }
    api, requests = build_api({ "message" => comment })

    assert_equal comment, api.send_comment("mid.post", "Hello")
    assert_request requests.first, :post, "/messages/mid.post/comments", body: { text: "Hello" }
  end

  def test_raw_send_comment_preserves_envelope_and_reply_payload
    result = { "message" => {} }
    api, requests = build_api(result)
    link = { "type" => "reply", "mid" => "mid.parent" }.freeze

    assert_equal result, api.raw.comments.send(message_id: "mid.post", text: "Reply", link:, format: "html")
    assert_request requests.first, :post, "/messages/mid.post/comments", body: { text: "Reply", link:, format: "html" }
  end

  def test_send_comment_accepts_symbol_keyed_adapter_response
    api, = build_api({ message: { body: { mid: "mid.comment" } } })

    assert_equal({ body: { mid: "mid.comment" } }, api.send_comment("mid.post", "Hello"))
  end

  def test_edit_comment_places_comment_id_in_query_not_body
    api, requests = build_api({ "success" => true })
    link = { type: "reply", mid: "mid.parent" }.freeze

    api.edit_comment("mid.post", "mid.comment", text: "Updated", link:, format: "markdown")

    assert_request requests.first, :put, "/messages/mid.post/comments?comment_id=mid.comment",
                   body: { text: "Updated", link:, format: "markdown" }
  end

  def test_raw_edit_comment_preserves_unsuccessful_result
    result = { "success" => false, "message" => "Not editable" }
    api, requests = build_api(result)

    assert_equal result, api.raw.comments.edit(message_id: "mid.post", comment_id: "mid.comment", text: "Updated")
    assert_request requests.first, :put, "/messages/mid.post/comments?comment_id=mid.comment", body: { text: "Updated" }
  end

  def test_delete_comment_uses_query_without_body
    result = { "success" => true }
    api, requests = build_api(result)

    assert_equal result, api.delete_comment("mid.post", "mid.comment")
    assert_request requests.first, :delete, "/messages/mid.post/comments?comment_id=mid.comment"
  end

  def test_raw_delete_comment_escapes_query_identifier
    api, requests = build_api

    api.raw.comments.delete(message_id: "mid.post", comment_id: "id+with&extra=value")

    assert_request requests.first, :delete, "/messages/mid.post/comments?comment_id=id%2Bwith%26extra%3Dvalue"
  end

  def test_high_level_send_rejects_comment_attachments
    api, requests = build_api

    assert_raises(ArgumentError) { api.send_comment("mid.post", "Hi", attachments: []) }
    assert_empty requests
  end

  def test_raw_send_rejects_comment_attachments
    api, requests = build_api

    assert_raises(ArgumentError) { api.raw.comments.send(message_id: "mid.post", text: "Hi", attachments: []) }
    assert_empty requests
  end

  def test_raw_edit_rejects_comment_attachments
    api, requests = build_api

    assert_raises(ArgumentError) do
      api.raw.comments.edit(message_id: "mid.post", comment_id: "mid.comment", text: "Hi", attachments: [])
    end
    assert_empty requests
  end

  def test_high_level_edit_rejects_message_only_options
    api, requests = build_api

    assert_raises(ArgumentError) { api.edit_comment("mid.post", "mid.comment", text: "Hi", notify: false) }
    assert_empty requests
  end

  def test_send_rejects_string_keyed_forward_links
    api, requests = build_api

    assert_raises(ArgumentError) do
      api.send_comment("mid.post", "Hi", link: { "type" => "forward", "mid" => "mid.other" })
    end
    assert_empty requests
  end

  def test_raw_edit_rejects_symbol_forward_links
    api, requests = build_api

    assert_raises(ArgumentError) do
      api.raw.comments.edit(message_id: "mid.post", comment_id: "mid.comment", text: "Hi", link: { type: :forward })
    end
    assert_empty requests
  end

  def test_invalid_link_reports_argument_error_before_request
    api, requests = build_api

    assert_raises(ArgumentError) { api.raw.comments.send(message_id: "mid.post", text: "Hi", link: "bad") }
    assert_empty requests
  end

  def test_false_link_is_rejected_before_request
    api, requests = build_api

    assert_raises(ArgumentError) { api.send_comment("mid.post", "Hi", link: false) }
    assert_empty requests
  end

  def test_conflicting_type_keys_cannot_forward_after_json_serialization
    api, requests = build_api
    link = { type: "reply", "type" => "forward", mid: "mid.other" }

    assert_raises(ArgumentError) { api.send_comment("mid.post", "Hi", link:) }
    assert_empty requests
  end

  def test_nullable_text_is_not_silently_dropped
    api, requests = build_api

    api.raw.comments.edit(message_id: "mid.post", comment_id: "mid.comment", text: nil)

    assert_request requests.first, :put, "/messages/mid.post/comments?comment_id=mid.comment", body: { text: nil }
  end

  def test_edit_builds_authenticated_json_http_request
    api, requests = build_api
    api.edit_comment("mid.post", "mid.comment", text: "Updated")
    request = requests.first

    http = api.client.send(:build_http_request, request, request.fetch(:url))

    assert_equal "PUT", http.method
    assert_equal "/messages/mid.post/comments?comment_id=mid.comment", http.path
    assert_equal "test-token", http["Authorization"]
    assert_equal "application/json", http["Content-Type"]
    assert_equal({ "text" => "Updated" }, JSON.parse(http.body))
  end

  def test_delete_builds_bodyless_http_request
    api, requests = build_api
    api.delete_comment("mid.post", "mid.comment")
    request = requests.first

    http = api.client.send(:build_http_request, request, request.fetch(:url))

    assert_equal "DELETE", http.method
    assert_equal "/messages/mid.post/comments?comment_id=mid.comment", http.path
    assert_nil http.body
    assert_nil http["Content-Type"]
  end

  def test_new_endpoints_preserve_api_error_handling
    api, = build_api({ "code" => "access.denied", "message" => "Denied" }, status: 403)
    operations = [
      -> { api.set_chat_admins(10, []) }, -> { api.remove_chat_admin(10, 42) },
      -> { api.get_video("video-token") }, -> { api.get_comments("mid.post") },
      -> { api.get_comment("mid.post", "mid.comment") }, -> { api.send_comment("mid.post", "Hello") },
      -> { api.edit_comment("mid.post", "mid.comment", text: "Updated") },
      -> { api.delete_comment("mid.post", "mid.comment") }
    ]

    operations.each do |operation|
      error = assert_raises(MaxApiClient::ApiError, &operation)
      assert_equal 403, error.status
      assert_equal "access.denied", error.code
    end
  end

  def test_get_all_chats_fails_locally_with_migration_hint
    api, requests = build_api

    error = assert_raises(MaxApiClient::UnsupportedEndpointError) { api.get_all_chats(count: 100) }

    assert_match(/webhook/, error.message)
    assert_empty requests
  end

  def test_raw_get_all_chats_fails_locally
    api, requests = build_api

    assert_raises(MaxApiClient::UnsupportedEndpointError) { api.raw.chats.get_all(marker: 0) }
    assert_empty requests
  end

  def test_get_chat_by_link_fails_locally_with_migration_hint
    api, requests = build_api

    error = assert_raises(MaxApiClient::UnsupportedEndpointError) { api.get_chat_by_link("https://max.ru/chat") }

    assert_match(/numeric chat ID/, error.message)
    assert_empty requests
  end

  def test_raw_get_chat_by_link_fails_locally
    api, requests = build_api

    assert_raises(MaxApiClient::UnsupportedEndpointError) { api.raw.chats.get_by_link(chat_link: "chat") }
    assert_empty requests
  end

  def test_numeric_chat_lookup_remains_supported
    api, requests = build_api

    api.get_chat(-10)

    assert_request requests.first, :get, "/chats/-10"
  end

  def test_add_chat_members_warns_once_but_preserves_request
    api, requests = build_api

    assert_output("", /deprecated; restricted since 2026-09-09, scheduled for removal on 2026-09-30\n\z/) do
      api.add_chat_members(10, [1, 2])
    end
    assert_request requests.first, :post, "/chats/10/members", body: { user_ids: [1, 2] }
    assert_equal 1, requests.size
  end

  def test_raw_add_chat_members_preserves_partial_failure_details
    result = { "success" => false, "failed_user_ids" => [42] }
    api, = build_api(result)
    response = nil

    assert_output("", /2026-09-30/) { response = api.raw.chats.add_chat_members(chat_id: 10, user_ids: [42]) }
    assert_equal result, response
  end

  def test_generic_raw_transport_remains_an_explicit_escape_hatch
    api, requests = build_api

    api.raw.get("chats", query: { count: 1 })

    assert_request requests.first, :get, "/chats?count=1"
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
end
# rubocop:enable Metrics/ClassLength
