module Api
  module V1
    class ProfileController < ApplicationController
      before_action :authorize_request!

      def show
        render json: profile_payload
      end

      def update
        Rails.logger.info("[profile] Raw params: #{params.inspect}")
        Rails.logger.info("[profile] Profile params: #{profile_params.to_h}")

        # Direct assignment for debugging
        profile_text_value = params.dig(:profile, :profile_text)
        Rails.logger.info("[profile] Direct profile_text: #{profile_text_value.present?}")

        current_user.profile_text = profile_text_value

        if current_user.save
          render json: profile_payload
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def profile_params
        # Handle both wrapped and unwrapped params
        if params[:profile].present?
          params.require(:profile).permit(:profile_text)
        else
          params.permit(:profile_text)
        end
      end

      def profile_payload
        {
          id: current_user.id,
          profile_text: current_user.profile_text,
          updated_at: current_user.updated_at
        }
      end
    end
  end
end
