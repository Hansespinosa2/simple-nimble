class CreateAccountsAndCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :display_name, null: false
      t.string :email
      t.string :role, null: false, default: "player"
      t.string :session_token, null: false

      t.timestamps
    end

    add_index :accounts, :email, unique: true
    add_index :accounts, :session_token, unique: true

    add_reference :characters, :account, foreign_key: true

    create_table :campaigns do |t|
      t.references :owner_account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.text :description
      t.string :invite_code, null: false

      t.timestamps
    end

    add_index :campaigns, :invite_code, unique: true

    create_table :campaign_memberships do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :role, null: false, default: "player"

      t.timestamps
    end

    add_index :campaign_memberships, [ :campaign_id, :account_id ], unique: true

    create_table :character_shares do |t|
      t.references :character, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.references :created_by_account, foreign_key: { to_table: :accounts }
      t.string :permission, null: false, default: "read"
      t.string :share_token, null: false

      t.timestamps
    end

    add_index :character_shares, [ :character_id, :campaign_id ], unique: true
    add_index :character_shares, :share_token, unique: true
  end
end
