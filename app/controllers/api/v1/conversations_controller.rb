class Api::V1::ConversationsController < ApplicationController
  before_action :authorize_request!

  def index
    conversations = Conversation.where(user: current_user)
    render json: conversations
  end

  def show
  end

  def create
    conversation = current_user.conversations.new(conversation_params)
    if conversation.save
      render json: conversation, status: :created
    else
      render json: { errors: conversation.errors.full_message }, status: :unprocessable_entity
    end
  end

  def update
  end

  def destroy
  end

  private

  def set_conversations
    @conversation = Conversation.find(params[:id])
  end

  def conversation_params
    params.require(:conversation).permit(:title)
  end
end
