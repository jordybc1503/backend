class AddAiConfigToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :ai_system_prompt, :text
    add_column :conversations, :ai_model, :string
    add_column :conversations, :ai_api_key, :text
  end
end
