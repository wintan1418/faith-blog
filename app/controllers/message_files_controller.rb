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
    blob = attachment.blob
    # ?inline=1 plays a voice note in the chat (or shows a file) instead of
    # saving it. Players ask for byte ranges to seek, so answer those.
    disposition = params[:inline].present? ? :inline : :attachment
    response.headers["Cache-Control"] = "private, max-age=300"
    if request.headers["Range"].present?
      send_blob_byte_range_data blob, request.headers["Range"], disposition: disposition
    else
      # The size up front lets phones show download progress.
      response.headers["Content-Length"] = blob.byte_size.to_s
      send_blob_stream blob, disposition: disposition
    end
  end
end
