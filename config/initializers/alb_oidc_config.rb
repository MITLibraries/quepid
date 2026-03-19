# frozen_string_literal: true

# ALB OIDC Authentication Configuration
# This initializer configures how Quepid handles authentication via AWS ALB with OIDC provider.

# The ALB OIDC flow:
# 1. ALB receives a request
# 2. ALB authenticates the user with an OIDC provider (e.g., Okta)
# 3. ALB injects headers: X-Amzn-Oidc-Data (JWT), X-Amzn-Oidc-Accesstoken, X-Amzn-Oidc-Identity
# 4. Request reaches Rails app with these headers
# 5. Quepid's middleware/set_current_user extracts user identity from headers
# 6. User is created/updated and session is established

# Configuration options are loaded from environment variables in customize_quepid.rb:
# - ALB_OIDC_ENABLED: Enable/disable ALB OIDC authentication
# - ALB_OIDC_VERIFY_SIGNATURE: Enable/disable JWT signature verification (default: false, trust ALB boundary)

module AlbOidcConfig
  # Standard OIDC claims we expect from ALB headers
  EXPECTED_CLAIMS = %i[sub email name picture].freeze

  # ALB injects these headers after OIDC authentication
  ALB_HEADERS = {
    data: 'X-Amzn-Oidc-Data',       # JWT with OIDC claims
    token: 'X-Amzn-Oidc-Accesstoken', # Access token from provider
    identity: 'X-Amzn-Oidc-Identity', # User identity string
  }.freeze

  # Validate ALB OIDC is properly configured
  def self.validate!
    return true unless Rails.application.config.alb_oidc_enabled

    Rails.logger.info('ALB OIDC authentication is enabled')
    Rails.logger.debug("  - Signature verification: #{Rails.application.config.alb_oidc_verify_signature}")
    Rails.logger.debug("  - Expected headers: #{ALB_HEADERS.values.join(', ')}")

    true
  end
end

# Run validation on app boot
AlbOidcConfig.validate! if Rails.application.config.alb_oidc_enabled
