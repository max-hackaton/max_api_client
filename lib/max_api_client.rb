# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require "securerandom"

require_relative "max_api_client/version"
require_relative "max_api_client/error"
require_relative "max_api_client/certificate_store"
require_relative "max_api_client/client"
require_relative "max_api_client/base_api"
require_relative "max_api_client/raw_api"
require_relative "max_api_client/polling"
require_relative "max_api_client/attachments"
require_relative "max_api_client/upload"
require_relative "max_api_client/api"

# Root namespace for the Max Bot API Ruby client.
module MaxApiClient
  class << self
    attr_accessor :logger
  end
end
