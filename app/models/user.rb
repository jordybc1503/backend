class User < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: true

  before_validation do
    self.email = email.downcase.strip if email.present?
  end
end
