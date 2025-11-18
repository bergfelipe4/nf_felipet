class AddCpfToUsers < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:users, :cpf)
      add_column :users, :cpf, :string
    end
  end
end
