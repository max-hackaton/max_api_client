# frozen_string_literal: true

module MaxApiClient
  # Builds a TLS trust store from the system defaults and an optional CA file.
  class CertificateStore
    def self.configure(http, ca_file:, verify_ssl:)
      http.use_ssl = true
      http.verify_mode = verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.cert_store = build(ca_file:) if verify_ssl
    end

    def self.build(ca_file:)
      OpenSSL::X509::Store.new.tap do |store|
        store.set_default_paths
        store.add_file(ca_file) if ca_file
      end
    end
  end
end
