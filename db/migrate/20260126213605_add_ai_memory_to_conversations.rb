class AddAiMemoryToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :ai_summary, :text
    add_column :conversations, :ai_summary_message_id, :bigint
    add_column :conversations, :ai_summary_updated_at, :datetime

    add_index :conversations, :ai_summary_message_id
  end
end
