# frozen_string_literal: true

module MaxApiClient
  # Base error type for gem-specific failures.
  class Error < StandardError; end

  # Raised locally when a removed or undocumented convenience endpoint is called.
  class UnsupportedEndpointError < Error; end

  # Error raised for non-successful API responses.
  class ApiError < Error
    attr_reader :status, :response

    def initialize(status, response = {})
      @status = status
      @response = response || {}
      super("#{status}: #{description}")
    end

    def code
      response["code"] || response[:code]
    end

    def description
      response["message"] || response[:message] || "Unknown API error"
    end
  end
end
