class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create

  def new
  end

  def create
    account = Account.authenticate_by(email: params[:email], password: params[:password])

    if account
      reset_session
      session[:account_id] = account.id
      session[:authenticated_account_id] = account.id
      redirect_to characters_path, notice: "Welcome back, #{account.display_name}."
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: "You have been signed out."
  end
end
