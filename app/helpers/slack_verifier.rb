# frozen_string_literal: true

require 'openssl'

module TimelogBot
  module Helpers
    class SlackVerifier
      TIMESTAMP_EXPIRY_SECONDS = 60 * 5 # 5 minutes

      def initialize(signing_secret: nil)
        @signing_secret = signing_secret || ENV.fetch('SLACK_SIGNING_SECRET')
      end

      # Verify that a request came from Slack
      # Returns true if valid, raises an error if not
      def verify!(request, cached_body: nil)
        timestamp = request.get_header('HTTP_X_SLACK_REQUEST_TIMESTAMP')
        signature = request.get_header('HTTP_X_SLACK_SIGNATURE')

        raise VerificationError, 'Missing timestamp header' unless timestamp
        raise VerificationError, 'Missing signature header' unless signature

        # Check timestamp to prevent replay attacks
        request_time = timestamp.to_i
        current_time = Time.now.to_i

        if (current_time - request_time).abs > TIMESTAMP_EXPIRY_SECONDS
          raise VerificationError, 'Request timestamp expired'
        end

        # Use cached body if provided, otherwise read from request
        body = cached_body || begin
          request.body.rewind
          content = request.body.read
          request.body.rewind
          content
        end
        
        # Debug logging in test mode
        if ENV['RACK_ENV'] == 'test'
          $logger.debug("SlackVerifier - Body read: #{body.inspect}")
          $logger.debug("SlackVerifier - Body length: #{body.length}")
        end

        # Compute expected signature
        sig_basestring = "v0:#{timestamp}:#{body}"
        computed_signature = 'v0=' + OpenSSL::HMAC.hexdigest(
          'SHA256',
          @signing_secret,
          sig_basestring
        )

        # Secure comparison to prevent timing attacks
        unless secure_compare(computed_signature, signature)
          if ENV['RACK_ENV'] == 'test'
            $logger.debug("SlackVerifier - Signature mismatch: computed=#{computed_signature}, received=#{signature}")
          end
          raise VerificationError, 'Invalid signature'
        end

        true
      end

      # Same as verify! but returns boolean instead of raising
      def verify(request, cached_body: nil)
        verify!(request, cached_body: cached_body)
        true
      rescue VerificationError => e
        $logger.warn("Slack verification failed: #{e.message}")
        false
      end

      private

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack('C*')
        r = 0
        b.each_byte { |byte| r |= byte ^ l.shift }
        r.zero?
      end

      class VerificationError < StandardError; end
    end
  end
end
