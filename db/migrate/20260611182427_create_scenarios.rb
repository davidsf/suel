class CreateScenarios < ActiveRecord::Migration[8.1]
  def change
    create_table :scenarios do |t|
      t.references :game_module, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :kind, null: false, default: "vsav"
      t.string :source_filename
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end
  end
end
