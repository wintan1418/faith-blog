# frozen_string_literal: true

# POST /waitlist — "Get the app" on the welcome page. Open to everyone (the
# guest gate lets it through). Turbo swaps the form for a thank-you; without
# JavaScript it redirects back to the welcome page with a flash.
#
# No email is sent yet: see AppWaitlistEntry for where a launch mailer goes.
class AppWaitlistEntriesController < ApplicationController
  BOT_MESSAGE = "We couldn't add you just now. Please try again in a moment."
  RATE_MESSAGE = "That's a lot of tries from here. Please wait a few minutes and try again."
  ANCHOR = "get-the-app"

  rate_limit to: 15, within: 10.minutes, only: :create, name: "waitlist", store: RateLimitStore.store,
             by: -> { request.remote_ip }, with: -> { reply_error(RATE_MESSAGE, status: :too_many_requests) }
  before_action :reject_bots!, only: :create

  def create
    @entry = AppWaitlistEntry.join(email: entry_params[:email], platform: entry_params[:platform].presence || "both",
                                   source: entry_params[:source].presence || "welcome", remote_ip: request.remote_ip)

    if @entry.persisted? && @entry.errors.empty?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("app_waitlist", partial: "app_waitlist_entries/thanks", locals: { entry: @entry }) }
        format.html { redirect_to root_path(anchor: ANCHOR), notice: thanks_message(@entry) }
      end
    else
      reply_error(@entry.errors.full_messages.first, entry: @entry, status: :unprocessable_entity)
    end
  end

  private

  def entry_params
    optional_params(:app_waitlist_entry).permit(:email, :platform, :source)
  end

  # Honeypot + "form shown at" stamp, shared with sign-up (SignupGuard).
  def reject_bots!
    reason = SignupGuard.bot_reason(params, remote_ip: request.remote_ip, turnstile: false)
    return unless reason

    SignupGuard.record_block!(reason, where: "app waitlist", remote_ip: request.remote_ip, email: entry_params[:email])
    reply_error(BOT_MESSAGE, status: :unprocessable_entity, fresh_token: true)
  end

  def reply_error(message, status:, entry: nil, fresh_token: false)
    entry ||= AppWaitlistEntry.new(email: entry_params[:email], platform: entry_params[:platform].presence || "both")
    # Keep the original "form shown at" stamp so a quick fix-and-resend isn't "too fast".
    token = fresh_token ? nil : params[SignupGuard::TOKEN_PARAM].presence
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("app_waitlist", partial: "app_waitlist_entries/form",
                                                                  locals: { entry: entry, error: message, form_token: token }),
               status: status
      end
      format.html { redirect_to root_path(anchor: ANCHOR), alert: message, status: :see_other }
      format.any { head status }
    end
  end

  def thanks_message(entry)
    "You're on the list. We'll email #{entry.email} when Brethreign is on #{entry.platform_name}."
  end
end
