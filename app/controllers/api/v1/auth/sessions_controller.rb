module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        before_action :authorize_request!, only: [ :verify]

        def create
          user = User.find_by(email: session_params[:email].to_s.downcase.strip)

          if user&.authenticate(session_params[:password])
            token = JsonWebToken.encode(user_id: user.id)
            render json: { user: user_response(user), token: token }, status: :ok
          else
            render json: { error: "Invalid email or password" }, status: :unauthorized
          end
        end

        def verify
          render json: { user: user_response(current_user) }, status: :ok
        end

        private

        def session_params
          params.require(:user).permit(:email, :password)
        end

        def user_response(user)
          { id: user.id, email: user.email }
        end
      end
    end
  end
end
