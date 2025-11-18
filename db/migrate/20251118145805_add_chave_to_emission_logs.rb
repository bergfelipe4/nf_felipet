class AddChaveToEmissionLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :emission_logs, :chave, :string
    add_index  :emission_logs, :chave, unique: true
  end
end
