class Api::V1::CaptionsController < ApplicationController
  before_action :authorize_request!
  before_action :set_conversation

  def create
    text = caption_params[:text].to_s.strip
    if text.blank?
      return render json: { errors: ["text is required"] }, status: :unprocessable_entity
    end

    speaker = caption_params[:speaker].to_s.strip.presence || "Interviewer"
    platform = caption_params[:platform].to_s.strip.presence
    formatted_text = format_caption_text(text:, speaker:, platform:)
    message_role = determine_speaker_role(speaker)

    if duplicate_caption?(formatted_text, message_role)
      return render json: { skipped: true }, status: :ok
    end

    caption_message = upsert_caption_message(formatted_text, message_role)

    assistant_message = nil
    assistant_error = nil

    if question_like?(text) && ai_throttle_allows?
      begin
        assistant_content = Ai::ChatCompletionService.new(conversation: @conversation).call
        assistant_message = @conversation.messages.create!(
          user: current_user,
          role: "assistant",
          content: assistant_content,
          status: "suggestion"
        )
      rescue Ai::ChatCompletionService::Error => e
        assistant_error = e.message
      end
    end

    begin
      Ai::ConversationSummaryService.new(conversation: @conversation).call
    rescue Ai::ConversationSummaryService::Error => e
      Rails.logger.warn("[ai-summary] #{e.message}")
    end

    render json: {
      caption_message: message_payload(caption_message),
      assistant_message: assistant_message ? message_payload(assistant_message) : nil,
      error: assistant_error
    }, status: :created
  end

  private

  def set_conversation
    @conversation = current_user.conversations.includes(:messages).find(params[:conversation_id])
  end

  def caption_params
    raw_params =
      if params[:caption].is_a?(ActionController::Parameters)
        params.require(:caption)
      else
        params
      end

    raw_params.permit(:text, :speaker, :platform, :timestamp)
  end

  def format_caption_text(text:, speaker:, platform:)
    speaker_label = platform.present? ? "#{speaker} (#{platform})" : speaker
    "#{speaker_label}: #{text}"
  end

  def determine_speaker_role(speaker)
    normalized = speaker.to_s.downcase.strip
    candidate_markers = ["you", "tú", "tu", "yo", "me"]

    candidate_markers.any? { |marker| normalized == marker } ? "user" : "interviewer"
  end

  def duplicate_caption?(formatted_text, role)
    last_message = last_message_by_role(role)
    return false unless last_message
    return false unless last_message.content == formatted_text

    last_message.updated_at > 6.seconds.ago
  end

  def upsert_caption_message(formatted_text, role)
    last_message = last_message_by_role(role)

    if last_message && last_message.created_at > 15.seconds.ago
      return last_message if last_message.content == formatted_text

      last_message.update!(content: formatted_text, status: "captured")
      last_message
    else
      @conversation.messages.create!(
        user: current_user,
        role: role,
        content: formatted_text,
        status: "captured"
      )
    end
  end

  def last_message_by_role(role)
    @conversation.messages.where(role: role).order(created_at: :desc).first
  end

  def ai_throttle_allows?
    last_assistant_message = @conversation.messages.where(role: "assistant").order(created_at: :desc).first
    return true unless last_assistant_message

    last_assistant_message.created_at < 8.seconds.ago
  end

  def question_like?(text)
    return true if text.include?("?")

    normalized = text.downcase.strip

    patterns = [
      /\b(can you|could you|would you|tell me|explain|how|what|why|when|where)\b/,
      /\b(walk me through|describe|give me an example|share an example)\b/,
      /\b(puedes|podrias|podrías|como|cómo|que|qué|por que|por qué|cuando|cuándo|donde|dónde)\b/
    ]

    patterns.any? { |pattern| normalized.match?(pattern) }
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
