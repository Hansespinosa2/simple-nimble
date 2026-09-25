class AccountsController < ApplicationController
  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      reset_session
      session[:account_id] = @account.id
      session[:authenticated_account_id] = @account.id
      redirect_to characters_path, notice: "Welcome, #{@account.display_name}. Your private workspace is ready."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(account: [ :display_name, :email, :password, :password_confirmation ])
    end
end
