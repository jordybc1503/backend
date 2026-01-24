class MeController < ApplicationController
  before_action :authorize_request!

  def show
    render json: { id: current_user.id, email: current_user.email }
  end
end
