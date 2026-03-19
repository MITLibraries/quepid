# frozen_string_literal: true

class AlbOidcMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Check if ALB OIDC is enabled and ALB headers are present
    if alb_oidc_enabled? && alb_headers_present?(env)
      # Build OmniAuth auth hash from ALB headers
      env['omniauth.auth'] = build_auth_hash_from_headers(env)
      env['omniauth.provider'] = 'alb_oidc'
    end

    @app.call(env)
  end

  private

  def alb_oidc_enabled?
    Rails.application.config.alb_oidc_enabled
  end

  def alb_headers_present?(env)
    env['HTTP_X_AMZN_OIDC_DATA'].present?
  end

  def build_auth_hash_from_headers(env)
    oidc_data = env['HTTP_X_AMZN_OIDC_DATA']
    access_token = env['HTTP_X_AMZN_OIDC_ACCESSTOKEN']

    begin
      # Decode JWT without verification (trust ALB network boundary)
      require 'jwt'
      payload = JWT.decode(oidc_data, nil, false)[0]
      claims = payload.deep_symbolize_keys

      # Build OmniAuth auth hash compatible with omniauth_callbacks_controller
      {
        'provider' => 'alb_oidc',
        'uid' => claims[:sub],
        'info' => {
          'email' => claims[:email],
          'name' => claims[:name],
          'image' => claims[:picture],
        },
        'credentials' => {
          'token' => access_token,
        },
        'extra' => {
          'raw_info' => claims,
        },
      }
    rescue JWT::DecodeError => e
      Rails.logger.error("ALB OIDC: Failed to decode JWT: #{e.message}")
      {}
    rescue StandardError => e
      Rails.logger.error("ALB OIDC: Unexpected error building auth hash: #{e.message}")
      {}
    end
  end
end

# Insert middleware into the stack
Rails.application.config.middleware.insert_before Rack::Runtime, AlbOidcMiddleware
