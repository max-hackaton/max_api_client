# frozen_string_literal: true

module MaxApiClient
  # High-level convenience wrapper over grouped Max Bot API endpoints.
  class Api
    attr_reader :raw, :upload, :client

    # rubocop:disable Metrics/ParameterLists
    def initialize(token:, base_url: Client::DEFAULT_BASE_URL, adapter: nil, open_timeout: nil, read_timeout: nil,
                   ca_file: Client::DEFAULT_CA_FILE, verify_ssl: true, logger: nil)
      @client = Client.new(
        token:,
        base_url:,
        adapter:,
        open_timeout:,
        read_timeout:,
        ca_file:,
        verify_ssl:,
        logger:
      )
      @raw = RawApi.new(client)
      @upload = Upload.new(self)
    end
    # rubocop:enable Metrics/ParameterLists

    # rubocop:disable Naming/AccessorMethodName
    def get_my_info
      raw.bots.get_my_info
    end
    # rubocop:enable Naming/AccessorMethodName

    def edit_my_info(**extra)
      raw.bots.edit_my_info(**extra)
    end

    # rubocop:disable Naming/AccessorMethodName
    def set_my_commands(commands)
      raw.bots.edit_my_commands(commands:)
    end
    # rubocop:enable Naming/AccessorMethodName

    def delete_my_commands
      set_my_commands([])
    end

    def get_all_chats(**extra)
      raw.chats.get_all(**extra)
    end

    def get_chat(chat_id)
      raw.chats.get_by_id(chat_id:)
    end

    def get_chat_by_link(chat_link)
      raw.chats.get_by_link(chat_link:)
    end

    def edit_chat_info(chat_id, **extra)
      raw.chats.edit(chat_id:, **extra)
    end

    def get_chat_membership(chat_id)
      raw.chats.get_chat_membership(chat_id:)
    end

    def get_chat_admins(chat_id)
      raw.chats.get_chat_admins(chat_id:)
    end

    def add_chat_members(chat_id, user_ids)
      raw.chats.add_chat_members(chat_id:, user_ids:)
    end

    def get_chat_members(chat_id, **extra)
      raw.chats.get_chat_members(chat_id:, **csv_query(extra, :user_ids))
    end

    def remove_chat_member(chat_id, user_id, block: nil)
      raw.chats.remove_chat_member(chat_id:, user_id:, block:)
    end

    def get_pinned_message(chat_id)
      raw.chats.get_pinned_message(chat_id:)
    end

    def pin_message(chat_id, message_id, **extra)
      raw.chats.pin_message(chat_id:, message_id:, notify: extra[:notify])
    end

    def unpin_message(chat_id)
      raw.chats.unpin_message(chat_id:)
    end

    def send_action(chat_id, action)
      raw.chats.send_action(chat_id:, action:)
    end

    def leave_chat(chat_id)
      raw.chats.leave_chat(chat_id:)
    end

    def send_message_to_chat(chat_id, text, **extra)
      message_from(raw.messages.send(chat_id:, text:, **extra))
    end

    def send_message_to_user(user_id, text, **extra)
      message_from(raw.messages.send(user_id:, text:, **extra))
    end

    def get_messages(chat_id = nil, **extra)
      raw.messages.get(chat_id:, **csv_query(extra, :message_ids))
    end

    def get_message(message_id)
      raw.messages.get_by_id(message_id:)
    end

    def edit_message(message_id, **extra)
      raw.messages.edit(message_id:, **extra)
    end

    def delete_message(message_id, **extra)
      raw.messages.delete(message_id:, **extra)
    end

    def answer_on_callback(callback_id, **extra)
      raw.messages.answer_on_callback(callback_id:, **extra)
    end

    # rubocop:disable Naming/AccessorMethodName
    def get_subscriptions
      raw.subscriptions.get_subscriptions
    end
    # rubocop:enable Naming/AccessorMethodName

    def subscribe(url, update_types: nil, secret: nil)
      raw.subscriptions.subscribe(url:, update_types:, secret:)
    end

    def unsubscribe(url)
      raw.subscriptions.unsubscribe(url:)
    end

    def poll_updates(types = [], marker: nil, timeout: Polling::DEFAULT_TIMEOUT,
                     retry_interval: Polling::DEFAULT_RETRY_INTERVAL, read_timeout: nil, &block)
      poller = Polling.new(
        self,
        types:,
        marker:,
        timeout:,
        retry_interval:,
        read_timeout:
      )

      return poller.each unless block

      poller.each(&block)
    end

    def upload_image(options)
      data = upload.image(**options)
      ImageAttachment.new(
        token: data[:token] || data["token"],
        photos: data[:photos] || data["photos"],
        url: data[:url] || data["url"]
      )
    end

    def upload_video(options)
      data = upload.video(**options)
      VideoAttachment.new(token: data[:token] || data["token"])
    end

    def upload_audio(options)
      data = upload.audio(**options)
      AudioAttachment.new(token: data[:token] || data["token"])
    end

    def upload_file(options)
      data = upload.file(**options)
      FileAttachment.new(token: data[:token] || data["token"])
    end

    private

    def normalize_types(types)
      return types unless types.is_a?(Array)

      types.join(",")
    end

    def csv_query(query, key)
      query.merge(key => normalize_types(query[key]))
    end

    def message_from(response)
      response.fetch("message") { response.fetch(:message) }
    end
  end
end
