class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_account

  private
    def current_account
      return @current_account if defined?(@current_account)

      @current_account = Account.find_by(id: session[:account_id])
    end
end
