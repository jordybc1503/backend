class Api::V1::CaptionsController < ApplicationController
  include ActionController::Live

  AUTO_RESPONSE_MODE = "auto".freeze
  MANUAL_LAST_INTERVIEWER_MODE = "manual_last_interviewer".freeze
  CAPTION_UPSERT_WINDOW = 90.seconds

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

    if auto_response_enabled? &&
         message_role == "interviewer" &&
         question_like?(text) &&
         ai_throttle_allows? &&
         !assistant_already_suggested_for_caption?(caption_message)
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

  def create_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Connection"] = "keep-alive"

    text = caption_params[:text].to_s.strip
    if text.blank?
      sse_write({ event: "error", data: { errors: ["text is required"] } })
      return
    end

    speaker = caption_params[:speaker].to_s.strip.presence || "Interviewer"
    platform = caption_params[:platform].to_s.strip.presence
    formatted_text = format_caption_text(text:, speaker:, platform:)
    message_role = determine_speaker_role(speaker)

    if duplicate_caption?(formatted_text, message_role)
      sse_write({ event: "skipped", data: { skipped: true } })
      return
    end

    caption_message = upsert_caption_message(formatted_text, message_role)
    sse_write({ event: "caption", data: message_payload(caption_message) })

    # Only trigger AI response when the INTERVIEWER speaks, not when the candidate/user speaks
    if auto_response_enabled? &&
         message_role == "interviewer" &&
         question_like?(text) &&
         ai_throttle_allows? &&
         !assistant_already_suggested_for_caption?(caption_message)
      # Try to acquire lock for AI processing - prevents concurrent AI requests
      lock_key = "ai_lock:conversation:#{@conversation.id}"

      if Rails.cache.read(lock_key)
        Rails.logger.info("[ai-throttle] AI processing already in progress for conversation #{@conversation.id}")
        sse_write({ event: "done", data: {} })
        return
      end

      begin
        # Set lock with 30 second expiration (should be enough for any AI response)
        Rails.cache.write(lock_key, true, expires_in: 30.seconds)

        accumulated_content = ""
        temp_message_id = SecureRandom.uuid

        sse_write({
          event: "assistant_start",
          data: { messageId: temp_message_id, role: "assistant" }
        })

        service = Ai::ChatCompletionService.new(conversation: @conversation)
        service.call_stream do |chunk|
          accumulated_content += chunk
          sse_write({
            event: "assistant_chunk",
            data: { messageId: temp_message_id, chunk: chunk }
          })
        end

        if accumulated_content.present?
          assistant_message = @conversation.messages.create!(
            user: current_user,
            role: "assistant",
            content: accumulated_content,
            status: "suggestion"
          )

          sse_write({
            event: "assistant_complete",
            data: message_payload(assistant_message)
          })
        end
      rescue Ai::ChatCompletionService::Error => e
        sse_write({ event: "error", data: { error: e.message } })
      ensure
        # Always release lock
        Rails.cache.delete(lock_key)
      end
    end

    begin
      Ai::ConversationSummaryService.new(conversation: @conversation).call
    rescue Ai::ConversationSummaryService::Error => e
      Rails.logger.warn("[ai-summary] #{e.message}")
    end

    sse_write({ event: "done", data: {} })
  rescue StandardError => e
    Rails.logger.error("[captions-stream] #{e.message}")
    sse_write({ event: "error", data: { error: "Internal server error" } }) rescue nil
  ensure
    response.stream.close rescue nil
  end

  private

  def sse_write(payload)
    event_name = payload[:event] || "message"
    data = payload[:data] || {}
    response.stream.write("event: #{event_name}\n")
    response.stream.write("data: #{data.to_json}\n\n")
    # Note: ActionController::Live::Buffer writes immediately, no flush needed
  rescue IOError
    # Client disconnected
  end

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

    raw_params.permit(:text, :speaker, :platform, :timestamp, :response_mode)
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

    if should_update_last_caption?(last_message, formatted_text)
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

  def should_update_last_caption?(last_message, formatted_text)
    return false unless last_message
    return false unless last_message.created_at > CAPTION_UPSERT_WINDOW.ago

    incremental_caption_update?(last_message.content, formatted_text)
  end

  def incremental_caption_update?(previous_text, next_text)
    previous = normalized_caption_body(previous_text)
    nxt = normalized_caption_body(next_text)
    return false if previous.blank? || nxt.blank?

    return true if nxt.start_with?(previous) || previous.start_with?(nxt)

    max_prefix = [previous.length, nxt.length].min
    return false if max_prefix.zero?

    common_prefix_length = 0
    while common_prefix_length < max_prefix && previous[common_prefix_length] == nxt[common_prefix_length]
      common_prefix_length += 1
    end

    common_prefix_length >= (max_prefix * 0.6).floor
  end

  def normalized_caption_body(text)
    text.to_s.split(":", 2).last.to_s.downcase.gsub(/\s+/, " ").strip
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
      /\b(can you|could you|would you|tell me|explain|how|what|why|when|where|who|which)\b/,
      /\b(walk me through|describe|give me an example|share an example|do you|are you|is there|are there)\b/,
      /\b(puedes|podrias|podrías|como|cómo|que|qué|por que|por qué|cuando|cuándo|donde|dónde|quien|quién|cual|cuál)\b/,
      /\b(explica|explicame|explícame|describe|describeme|descríbeme|dime|dimé|cuéntame|cuentame|háblame|hablame)\b/,
      /\b(muéstrame|muestrame|ayúdame|ayudame|necesito|quiero saber)\b/
    ]

    patterns.any? { |pattern| normalized.match?(pattern) }
  end

  def response_mode
    raw = caption_params[:response_mode].to_s
    raw == MANUAL_LAST_INTERVIEWER_MODE ? MANUAL_LAST_INTERVIEWER_MODE : AUTO_RESPONSE_MODE
  end

  def auto_response_enabled?
    response_mode == AUTO_RESPONSE_MODE
  end

  def assistant_already_suggested_for_caption?(caption_message)
    @conversation.messages
                 .where(role: "assistant", status: "suggestion")
                 .where("created_at >= ?", caption_message.created_at)
                 .exists?
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
