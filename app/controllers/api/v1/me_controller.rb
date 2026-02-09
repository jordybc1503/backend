module Api
  module V1
    class MeController < ApplicationController
      before_action :authorize_request!

      def show
        render json: user_payload
      end

      def update
        if current_user.update(user_params)
          render json: user_payload
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def user_params
        params.require(:user).permit(:name, :email)
      end

      def user_payload
        {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          profile_text: current_user.profile_text
        }
      end
    end
  end
end
