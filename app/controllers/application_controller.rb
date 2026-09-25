class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_account

  private
    def current_account
      return @current_account if defined?(@current_account)

      authenticated_id = session[:authenticated_account_id]
      @current_account = if authenticated_id.present? && authenticated_id == session[:account_id]
        Account.find_by(id: authenticated_id)
      end
    end

    def require_account
      return if current_account.present?

      session[:account_id] = nil
      session[:authenticated_account_id] = nil
      redirect_to new_session_path, alert: "Sign in to continue."
    end
end
