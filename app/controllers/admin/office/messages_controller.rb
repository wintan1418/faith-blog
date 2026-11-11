# frozen_string_literal: true

class Admin::Office::MessagesController < Admin::Office::BaseController
  rate_limit to: 20, within: 1.minute, only: :create, with: -> { too_many }

  before_action :set_conversation

  def create
    content = params.dig(:message, :content).to_s.strip
    if content.blank?
      head :unprocessable_entity and return
    end
    if @conversation.busy?
      respond_with_notice("Still writing the last reply. Give it a moment.") and return
    end

    sent = @conversation.messages.create!(role: :user, content: content)
    @conversation.title_from!(content)
    @conversation.thinking!(true)
    OfficeReplyJob.perform_later(@conversation.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("office_messages", partial: "admin/office/messages/message", locals: { message: sent }),
          turbo_stream.replace("office_status", partial: "admin/office/conversations/status", locals: { conversation: @conversation }),
          turbo_stream.replace("office_composer", partial: "admin/office/conversations/composer", locals: { conversation: @conversation })
        ]
      end
      format.html { redirect_to admin_office_conversation_path(@conversation) }
    end
  end

  private

  def set_conversation
    @conversation = conversations.find(params[:conversation_id])
  end

  def too_many
    respond_with_notice("That's a lot of messages in a minute. Wait a moment and try again.", status: :too_many_requests)
  end

  def respond_with_notice(text, status: :unprocessable_entity)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("office_notice", html: ERB::Util.h(text)), status: status
      end
      format.html { redirect_to admin_office_conversation_path(params[:conversation_id]), alert: text }
    end
    true
  end
end
