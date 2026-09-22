class SessionsController < ApplicationController
  def new
    @account = Account.new
  end

  def create
    account_params = params.expect(account: [ :display_name, :email, :role ])
    @account = account_params[:email].present? ? Account.find_or_initialize_by(email: account_params[:email].downcase.strip) : Account.new
    @account.assign_attributes(account_params)

    if @account.save
      reset_session
      session[:account_id] = @account.id
      redirect_to characters_path, notice: "Welcome, #{@account.display_name}. This is your character workspace."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "You are back in the shared workspace."
  end
end
