class AddPasswordDigestToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :password_digest, :string
    add_index :accounts, "lower(email)", unique: true, name: "index_accounts_on_lower_email"
  end
end
