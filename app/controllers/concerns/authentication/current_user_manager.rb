# frozen_string_literal: true

module Authentication
  module CurrentUserManager
    extend ActiveSupport::Concern

    included do
      helper_method :current_user
    end

    private

    def current_user
      @current_user
    end

    def authenticate_api!
      return true if current_user

      render json:   { reason: 'Unauthorized!' },
             status: :unauthorized
    end

    def check_current_user_locked!
      return true unless current_user&.locked?

      clear_user_session
      self.status = :unauthorized
      self.response_body = { reason: 'Locked' }.to_json
    end

    def set_current_user
      if @current_user.present?
        session[:current_user_id] = @current_user.id
        return
      end

      # Check for ALB OIDC authentication before checking session
      if authenticate_from_alb_headers
        return
      end

      if session[:current_user_id] && User.exists?(session[:current_user_id])
        @current_user = User.find(session[:current_user_id])
      else
        clear_user_session
      end
    end

    def authenticate_from_alb_headers
      return false unless Rails.application.config.alb_oidc_enabled
      return false unless request.headers['X-Amzn-Oidc-Data'].present?

      begin
        require 'jwt'
        oidc_data = request.headers['X-Amzn-Oidc-Data']
        payload = JWT.decode(oidc_data, nil, false)[0]
        claims = payload.deep_symbolize_keys

        # Extract user info from ALB OIDC claims
        email = claims[:email]
        return false if email.blank?

        # Find or create user
        if Rails.application.config.signup_enabled
          user = User.find_or_initialize_by(email: email)
        else
          user = User.find_by(email: email)
          return false if user.nil?
        end

        # Update user info from claims
        user.name = claims[:name] if claims[:name].present?
        user.profile_pic = claims[:picture] if claims[:picture].present?
        user.password = 'fake' if user.password.blank?
        user.agreed = true
        user.num_logins ||= 0
        user.num_logins += 1

        if user.save
          @current_user = user
          session[:current_user_id] = user.id
          ahoy.authenticate(user)
          return true
        end
      rescue JWT::DecodeError => e
        Rails.logger.error("ALB OIDC: Failed to decode JWT: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("ALB OIDC: Error during ALB authentication: #{e.message}")
      end

      false
    end

    def require_login
      unless @current_user
        # check if we are redirected from the case page, and if so support unfurling
        # by populating the flash so it renders in the start.html.erb layout.
        flash[:unfurl] = Case.find_by(id: params[:id]) if 'core' == params[:controller] && 'index' == params[:action] && params[:id]
        redirect_to new_session_path
      end
    end

    def auto_login user
      @current_user = user
    end

    def clear_user_session
      @current_user             = nil
      session[:current_user_id] = nil
    end
  end
end
