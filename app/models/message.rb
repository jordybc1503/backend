class Message < ApplicationRecord
  belongs_to :conversation, touch: true
  belongs_to :user

  validates :content, presence: true
  validates :role, presence: true
end
