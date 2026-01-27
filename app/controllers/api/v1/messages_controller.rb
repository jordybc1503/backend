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
      assistant_message = nil
      assistant_error = nil

      if message.role == "user"
        begin
          assistant_content = Ai::ChatCompletionService.new(conversation: @conversation).call
          assistant_message = @conversation.messages.create!(
            user: current_user,
            role: "assistant",
            content: assistant_content,
            status: "completed"
          )
        rescue Ai::ChatCompletionService::Error => e
          assistant_error = e.message
        end
      end

      render json: {
        message: message_payload(message),
        assistant_message: assistant_message ? message_payload(assistant_message) : nil,
        error: assistant_error,
        conversation: conversation_payload(@conversation)
      }, status: :created
    else
      render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = current_user.conversations.includes(:messages).find(params[:conversation_id])
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

  def conversation_payload(conversation)
    last_message = conversation.messages.order(created_at: :desc).first

    {
      id: conversation.id,
      title: conversation.title,
      updatedAt: conversation.updated_at,
      updated_at: conversation.updated_at,
      lastMessage: last_message&.content,
      last_message: last_message&.content,
      aiSystemPrompt: conversation.ai_system_prompt,
      ai_system_prompt: conversation.ai_system_prompt,
      aiModel: conversation.ai_model,
      ai_model: conversation.ai_model,
      aiApiKey: conversation.ai_api_key,
      ai_api_key: conversation.ai_api_key
    }
  end
end
