# frozen_string_literal: true

# A photo, voice note or document from a chat, downloaded from brethreign.com
# under its original name ("Report.pdf", not "cloudinaryfile.pdf"). Only the
# people in that conversation can get it.
#
# The file is streamed through our own site rather than redirecting to the file
# store: the store names downloads itself (or not at all for Word/PowerPoint
# files), and in the apps a redirect to another site opens the browser.
class MessageFilesController < ApplicationController
  include ActiveStorage::Streaming

  ATTACHMENT_NAMES = %w[images documents voice_note].freeze

  before_action :authenticate_user!
  skip_after_action :track_page_view

  def show
    conversation = current_user.conversations.find(params[:conversation_id])
    message = conversation.messages.visible.find(params[:message_id])
    raise ActiveRecord::RecordNotFound if message.removed?

    attachment = ActiveStorage::Attachment.where(record: message, name: ATTACHMENT_NAMES).find(params[:id])
    # The size up front lets phones show download progress.
    response.headers["Content-Length"] = attachment.blob.byte_size.to_s
    send_blob_stream attachment.blob, disposition: :attachment
  end
end
