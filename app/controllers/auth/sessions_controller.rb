module Auth
  class SessionsController < ApplicationController
    def create
      user = User.find_by(email: params[:email].to_s.downcase.strip)

      if user&.authenticate(params[:password])
        token = JsonWebToken.encode(user_id: user.id)
        render json: { user: user_response(user), token: token }, status: :ok
      else
        render json: { error: "Invalid email or password" }, status: :unauthorized
      end
    end

    private

    def user_response(user)
      { id: user.id, email: user.email }
    end
  end
end
