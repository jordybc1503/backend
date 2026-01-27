class Api::V1::ConversationsController < ApplicationController
  before_action :authorize_request!
  before_action :set_conversation, only: %i[show update destroy]

  def index
    conversations = current_user.conversations.includes(:messages).order(updated_at: :desc)
    render json: conversations.map { |conversation| conversation_payload(conversation) }
  end

  def show
    render json: conversation_payload(@conversation, include_messages: true)
  end

  def create
    conversation = current_user.conversations.new(conversation_params)
    if conversation.save
      render json: conversation_payload(conversation), status: :created
    else
      render json: { errors: conversation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @conversation.update(conversation_params)
      render json: conversation_payload(@conversation)
    else
      render json: { errors: @conversation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @conversation.destroy
    head :no_content
  end

  private

  def set_conversation
    @conversation = current_user.conversations.includes(:messages).find(params[:id])
  end

  def conversation_params
    raw_params =
      if params[:conversation].is_a?(ActionController::Parameters)
        params.require(:conversation)
      else
        params
      end

    raw_params.permit(:title, :ai_system_prompt, :ai_model, :ai_api_key)
  end

  def conversation_payload(conversation, include_messages: false)
    last_message = last_message_for(conversation)

    payload = {
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
      ai_api_key: conversation.ai_api_key,
      aiSummary: conversation.ai_summary,
      ai_summary: conversation.ai_summary,
      aiSummaryMessageId: conversation.ai_summary_message_id,
      ai_summary_message_id: conversation.ai_summary_message_id,
      aiSummaryUpdatedAt: conversation.ai_summary_updated_at,
      ai_summary_updated_at: conversation.ai_summary_updated_at
    }

    payload[:messages] = serialized_messages(conversation) if include_messages
    payload
  end

  def last_message_for(conversation)
    if conversation.association(:messages).loaded?
      conversation.messages.max_by(&:created_at)
    else
      conversation.messages.order(created_at: :desc).first
    end
  end

  def serialized_messages(conversation)
    conversation.messages.order(:created_at).map { |message| message_payload(message) }
  end

  def message_payload(message)
    {
      id: message.id,
      conversationId: message.conversation_id,
      conversation_id: message.conversation_id,
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
