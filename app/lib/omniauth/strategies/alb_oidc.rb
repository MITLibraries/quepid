# frozen_string_literal: true

require 'jwt'

module OmniAuth
  module Strategies
    class AlbOidc < OmniAuth::Strategy
      option :name, 'alb_oidc'
      option :verify_signature, false  # ALB boundary is trusted
      option :issuer, 'https://oidc.amazonaws.com/'

      def request_phase
        # ALB already authenticated the user, no redirect needed
        # Skip directly to callback
        call_app!
      end

      def callback_phase
        # Read ALB headers injected by AWS ALB
        oidc_data = request.headers['X-Amzn-Oidc-Data']

        if oidc_data.blank?
          fail!(:no_alb_data, 'Missing X-Amzn-Oidc-Data header')
          return
        end

        begin
          # Decode JWT from ALB header (decode without verification for now)
          # ALB signs with its own key; we trust the ALB network boundary
          payload = JWT.decode(oidc_data, nil, false)[0]
          @claims = payload.deep_symbolize_keys
          @uid = @claims[:sub]

          # Call the parent class callback_phase to complete the flow
          super
        rescue JWT::DecodeError => e
          fail!(:invalid_token, "Failed to decode JWT: #{e.message}")
        rescue StandardError => e
          fail!(:unknown_error, "Unexpected error: #{e.message}")
        end
      end

      uid { @uid }

      info do
        {
          email: @claims[:email],
          name: @claims[:name],
          image: @claims[:picture]
        }
      end

      extra do
        {
          raw_info: @claims,
          access_token: request.headers['X-Amzn-Oidc-Accesstoken']
        }
      end

      credentials do
        {
          token: request.headers['X-Amzn-Oidc-Accesstoken']
        }
      end

      private

      def call_app!
        @app.call(env)
      end
    end
  end
end
