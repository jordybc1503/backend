class Api::V1::MessagesController < ApplicationController
  before_action :authorize_request!
  before_action :set_conversation

  def index
    messages = @conversation.messages.order(:created_at)
    render json: { messages: messages.map { |message| message_payload(message) } }
  end

  def create
    message = @conversation.messages.new(message_params)
    message.user = current_user
    message.role = message.role.presence || "user"

    if message.save
      render json: { message: message_payload(message) }, status: :created
    else
      render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end

  def message_params
    raw_params =
      if params[:message].is_a?(ActionController::Parameters)
        params.require(:message)
      else
        params
      end

    raw_params.permit(:role, :content, :status)
  end

  def message_payload(message)
    {
      id: message.id,
      conversationId: message.conversation_id,
      conversation_id: message.conversation_id,
      userId: message.user_id,
      user_id: message.user_id,
      role: message.role,
      content: message.content,
      status: message.status,
      createdAt: message.created_at,
      created_at: message.created_at,
      updatedAt: message.updated_at,
      updated_at: message.updated_at
    }
  end
end
