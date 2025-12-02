class AddCnpjToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :cnpj, :string
  end
end
