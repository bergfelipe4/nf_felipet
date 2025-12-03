class AddFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :razao_social, :string
    add_column :users, :nome_fantasia, :string
    add_column :users, :telefone, :string
    add_column :users, :inscricao_estadual, :string
  end
end
