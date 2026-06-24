class AddCategoryToScenarios < ActiveRecord::Migration[8.1]
  def change
    add_column :scenarios, :category, :string
  end
end
