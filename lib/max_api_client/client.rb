# frozen_string_literal: true

module MaxApiClient
  # HTTP transport client responsible for authenticated API requests.
  class Client
    DEFAULT_BASE_URL = "https://platform-api2.max.ru"
    DEFAULT_CA_FILE = File.expand_path("../../certs/russian_trusted_root_ca.pem", __dir__)
    REQUEST_CLASSES = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete
    }.freeze

    attr_reader :token, :base_url, :ca_file, :verify_ssl

    # rubocop:disable Metrics/ParameterLists
    def initialize(token:, base_url: DEFAULT_BASE_URL, adapter: nil, open_timeout: nil, read_timeout: nil,
                   ca_file: DEFAULT_CA_FILE, verify_ssl: true, logger: nil)
      @token = token
      @base_url = base_url
      @adapter = adapter
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @ca_file = ca_file
      @verify_ssl = verify_ssl
      @logger = logger || MaxApiClient.logger
    end
    # rubocop:enable Metrics/ParameterLists

    # rubocop:disable Metrics/ParameterLists
    def call(method:, path: nil, query: nil, body: nil, path_params: nil, headers: nil, url: nil, raw_body: nil,
             parse_json: true, open_timeout: nil, read_timeout: nil)
      request = build_request(
        method:,
        path:,
        query:,
        body:,
        path_params:,
        headers:,
        url:,
        raw_body:,
        parse_json:,
        open_timeout:,
        read_timeout:
      )

      log_debug("max_api_client.request", loggable_request(request))

      response = @adapter ? @adapter.call(request) : perform_request(request)

      log_debug("max_api_client.response", loggable_response(response))
      response
    end
    # rubocop:enable Metrics/ParameterLists

    private

    # rubocop:disable Metrics/ParameterLists
    def build_request(method:, path:, query:, body:, path_params:, headers:, url:, raw_body:, parse_json:,
                      open_timeout:, read_timeout:)
      {
        method: method.to_sym,
        url: build_url(path:, path_params:, query:, url:),
        path: path,
        path_params: path_params,
        query: query,
        body: body,
        raw_body: raw_body,
        headers: default_headers(headers, body:, raw_body:),
        parse_json: parse_json,
        open_timeout: open_timeout,
        read_timeout: read_timeout
      }
    end
    # rubocop:enable Metrics/ParameterLists

    # rubocop:disable Metrics/AbcSize
    def build_url(path:, path_params:, query:, url:)
      uri = if url
              URI(url)
            else
              URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", expand_path(path.to_s, path_params))
            end

      params = URI.decode_www_form(String(uri.query))
      query.to_h.each do |key, value|
        next if value.nil? || value == false

        params << [key.to_s, value.to_s]
      end
      uri.query = params.empty? ? nil : URI.encode_www_form(params)
      uri
    end
    # rubocop:enable Metrics/AbcSize

    def expand_path(path, path_params)
      path_params.to_h.each_with_object(path.dup) do |(key, value), expanded|
        expanded.gsub!("{#{key}}", URI.encode_www_form_component(value.to_s))
      end
    end

    def default_headers(headers, body:, raw_body:)
      {
        "Authorization" => token.to_s
      }.tap do |result|
        result["Content-Type"] = "application/json" if body && raw_body.nil?
        result.merge!(headers.to_h)
      end
    end

    def perform_request(request)
      uri = request.fetch(:url)
      response = configured_http(
        uri,
        open_timeout: request[:open_timeout],
        read_timeout: request[:read_timeout]
      ).request(build_http_request(request, uri))

      {
        status: response.code.to_i,
        data: parse_response_body(response.body.to_s, parse_json: request[:parse_json]),
        headers: response.to_hash
      }
    end

    def configured_http(uri, open_timeout:, read_timeout:)
      open_timeout ||= @open_timeout
      read_timeout ||= @read_timeout

      Net::HTTP.new(uri.host, uri.port).tap do |http|
        CertificateStore.configure(http, ca_file:, verify_ssl:) if uri.scheme == "https"
        http.open_timeout = open_timeout if open_timeout
        http.read_timeout = read_timeout if read_timeout
      end
    end

    def build_http_request(request, uri)
      REQUEST_CLASSES.fetch(request.fetch(:method)).new(uri).tap do |http_request|
        request.fetch(:headers).each do |key, value|
          http_request[key] = value
        end

        http_request.body = request_body(request)
      end
    end

    def request_body(request)
      return request[:raw_body] if request[:raw_body]
      return JSON.generate(request[:body]) if request[:body]

      nil
    end

    def parse_response_body(body, parse_json:)
      return body unless parse_json
      return {} if body.empty?

      JSON.parse(body)
    end

    def log_debug(message, payload)
      @logger&.debug("#{message} #{payload.inspect}")
    end

    def loggable_request(request)
      request.merge(
        headers: mask_headers(request[:headers]),
        url: request[:url].to_s
      )
    end

    def loggable_response(response)
      response.merge(headers: mask_headers(response[:headers]))
    end

    def mask_headers(headers)
      headers.to_h.dup.tap do |result|
        result["Authorization"] = "[FILTERED]" if result.key?("Authorization")
        result["authorization"] = "[FILTERED]" if result.key?("authorization")
      end
    end
  end
end
