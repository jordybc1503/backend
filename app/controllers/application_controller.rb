class ApplicationController < ActionController::API
  attr_reader :current_user

  private

  def authorize_request!
    token = bearer_token
    return render_unauthorized("Missing token") if token.nil?

    decoded = JsonWebToken.decode(token)
    return render_unauthorized("Invalid token") if decoded.nil?

    @current_user = User.find_by(id: decoded[:user_id])
    render_unauthorized("User not found") if @current_user.nil?
  rescue JWT::ExpiredSignature
    render_unauthorized("Token expired")
  rescue JWT::DecodeError
    render_unauthorized("Invalid token")
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    # Expect: "Bearer <token>"
    header.split(" ").last if header.start_with?("Bearer ")
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end
end
