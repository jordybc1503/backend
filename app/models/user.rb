class User < ApplicationRecord
  has_secure_password
  has_many :conversations, dependent: :destroy
  has_many :messages, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  before_validation do
    self.email = email.downcase.strip if email.present?
  end
end
