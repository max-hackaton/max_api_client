# frozen_string_literal: true

module MaxApiClient
  # Low-level grouped access to Max Bot API endpoint families.
  class RawApi < BaseApi
    attr_reader :client

    def bots
      @bots ||= build_api(BotsApi)
    end

    def chats
      @chats ||= build_api(ChatsApi)
    end

    def messages
      @messages ||= build_api(MessagesApi)
    end

    def videos
      @videos ||= build_api(VideosApi)
    end

    def comments
      @comments ||= build_api(CommentsApi)
    end

    def subscriptions
      @subscriptions ||= build_api(SubscriptionsApi)
    end

    def uploads
      @uploads ||= build_api(UploadsApi)
    end

    private

    def build_api(klass)
      klass.new(client)
    end
  end

  # Raw bot profile endpoints.
  class BotsApi < BaseApi
    # rubocop:disable Naming/AccessorMethodName
    def get_my_info
      get("me")
    end
    # rubocop:enable Naming/AccessorMethodName

    # Compatibility for callers that edited commands through the former profile endpoint.
    def edit_my_info(**extra)
      return edit_my_commands(commands: extra[:commands]) if extra.keys == [:commands]

      raise ArgumentError, "Bot profile editing is no longer supported; use edit_my_commands(commands: ...)"
    end

    def edit_my_commands(commands:)
      patch("me/commands", body: { commands: })
    end
  end

  # Raw chat management endpoints.
  class ChatsApi < BaseApi
    # Removed by MAX in June 2026. Keep the entry point to explain migration.
    def get_all(**_extra)
      raise UnsupportedEndpointError,
            "GET /chats is no longer supported; store chat_id values from webhook events"
    end

    def get_by_id(chat_id:)
      get("chats/{chat_id}", path_params: { chat_id: })
    end

    def get_by_link(chat_link:) # rubocop:disable Lint/UnusedMethodArgument
      raise UnsupportedEndpointError,
            "Chat lookup by link is not supported; use get_by_id(chat_id: ...) with a stored numeric chat ID"
    end

    def edit(chat_id:, **extra)
      patch("chats/{chat_id}", path_params: { chat_id: }, body: extra)
    end

    def get_chat_membership(chat_id:)
      get("chats/{chat_id}/members/me", path_params: { chat_id: })
    end

    def get_chat_admins(chat_id:)
      get("chats/{chat_id}/members/admins", path_params: { chat_id: })
    end

    def set_chat_admins(chat_id:, admins:, marker: nil)
      post("chats/{chat_id}/members/admins", path_params: { chat_id: }, body: compact_nil(admins:, marker:))
    end

    def remove_chat_admin(chat_id:, user_id:)
      delete("chats/{chat_id}/members/admins/{user_id}", path_params: { chat_id:, user_id: })
    end

    # Preserve the restricted endpoint without a date-dependent client-side cutoff.
    def add_chat_members(chat_id:, user_ids:)
      warn "max_api_client: add_chat_members is deprecated; restricted since 2026-09-09, " \
           "scheduled for removal on 2026-09-30"
      post("chats/{chat_id}/members", path_params: { chat_id: }, body: { user_ids: })
    end

    def get_chat_members(chat_id:, **query)
      get("chats/{chat_id}/members", path_params: { chat_id: }, query:)
    end

    def remove_chat_member(chat_id:, user_id:, block: nil)
      delete("chats/{chat_id}/members", path_params: { chat_id: }, query: compact_nil(user_id:, block:))
    end

    def get_pinned_message(chat_id:)
      get("chats/{chat_id}/pin", path_params: { chat_id: })
    end

    def pin_message(chat_id:, message_id:, notify: nil)
      put("chats/{chat_id}/pin", path_params: { chat_id: }, body: compact_nil(message_id:, notify:))
    end

    def unpin_message(chat_id:)
      delete("chats/{chat_id}/pin", path_params: { chat_id: })
    end

    def send_action(chat_id:, action:)
      post("chats/{chat_id}/actions", path_params: { chat_id: }, body: { action: })
    end

    def leave_chat(chat_id:)
      delete("chats/{chat_id}/members/me", path_params: { chat_id: })
    end
  end

  # Raw message delivery and mutation endpoints.
  class MessagesApi < BaseApi
    ATTACHMENT_NOT_READY_CODE = "attachment.not.ready"
    ATTACHMENT_NOT_READY_DELAY = 1

    def get(**query)
      super("messages", query:)
    end

    def get_by_id(message_id:)
      call_api(:get, "messages/{message_id}", path_params: { message_id: })
    end

    def send(chat_id: nil, user_id: nil, disable_link_preview: nil, **body)
      post("messages", query: compact_nil(chat_id:, user_id:, disable_link_preview:), body:)
    rescue ApiError => e
      raise unless e.code == ATTACHMENT_NOT_READY_CODE

      sleep(ATTACHMENT_NOT_READY_DELAY)
      send(chat_id:, user_id:, disable_link_preview:, **body)
    end

    def edit(message_id:, **body)
      put("messages", query: { message_id: }, body:)
    end

    def delete(message_id:)
      super("messages", query: { message_id: })
    end

    def answer_on_callback(callback_id:, **body)
      post("answers", query: { callback_id: }, body:)
    end
  end

  # Raw metadata endpoint for uploaded video attachments (not an upload operation).
  class VideosApi < BaseApi
    def get_by_token(video_token:)
      get("videos/{video_token}", path_params: { video_token: })
    end
  end

  # Raw channel-comment endpoints. Comments have a narrower body than messages.
  class CommentsApi < BaseApi
    def get(message_id:, **query)
      call_api(:get, "messages/{message_id}/comments", path_params: { message_id: }, query:)
    end

    def get_by_id(message_id:, comment_id:)
      call_api(:get, "messages/{message_id}/comments/{comment_id}", path_params: { message_id:, comment_id: })
    end

    def send(message_id:, text:, link: nil, format: nil)
      post("messages/{message_id}/comments", path_params: { message_id: }, body: comment_body(text, link, format))
    end

    def edit(message_id:, comment_id:, text:, link: nil, format: nil)
      put("messages/{message_id}/comments", path_params: { message_id: }, query: { comment_id: },
          body: comment_body(text, link, format))
    end

    def delete(message_id:, comment_id:)
      call_api(:delete, "messages/{message_id}/comments", path_params: { message_id: }, query: { comment_id: })
    end

    private

    def comment_body(text, link, format)
      unless link.nil? || reply_link?(link)
        raise ArgumentError, "Comments only support reply links; forwarding is not supported"
      end

      { text: }.merge(compact_nil(link:, format:))
    end

    def reply_link?(link)
      return false unless link.is_a?(Hash)

      types = [:type, "type"].select { |key| link.key?(key) }.map { |key| link[key].to_s }
      !types.empty? && types.all?("reply")
    end
  end

  # Raw update subscription endpoints.
  class SubscriptionsApi < BaseApi
    # rubocop:disable Naming/AccessorMethodName
    def get_subscriptions
      get("subscriptions")
    end
    # rubocop:enable Naming/AccessorMethodName

    def subscribe(url:, update_types: nil, secret: nil)
      post("subscriptions", body: compact_nil(url:, update_types:, secret:))
    end

    def unsubscribe(url:)
      delete("subscriptions", query: { url: })
    end

    def get_updates(read_timeout: nil, **query)
      get("updates", query:, read_timeout:)
    end
  end

  # Raw upload URL acquisition endpoints.
  class UploadsApi < BaseApi
    def get_upload_url(type:)
      post("uploads", query: { type: })
    end
  end
end
