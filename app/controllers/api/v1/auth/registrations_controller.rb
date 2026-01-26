module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        # POST /api/v1/auth/register
        # Registers a new user
        # Params:
        # - email: string (required)
        # - password: string (required)
        # - password_confirmation: string (required)
        def create
          user = User.new(user_params)

          if user.save
            token = JsonWebToken.encode(user_id: user.id)
            render json: { user: user_response(user), token: token }, status: :created
          else
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def user_params
          params.require(:user).permit(:email, :password, :password_confirmation, :name)
        end

        def user_response(user)
          { id: user.id, email: user.email }
        end
      end
    end
  end
end
