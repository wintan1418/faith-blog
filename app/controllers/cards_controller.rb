# frozen_string_literal: true

require "rqrcode"

# The digital business card: brethreign.com/in/username. A shareable card
# with a QR code, "Save contact" (a vCard with only professional details,
# never the private Brethren Card) and a short public summary.
class CardsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  before_action :set_member

  def show
    @owner = user_signed_in? && current_user == @member
    raise ActiveRecord::RecordNotFound unless visible?

    @card_url = card_url(@member.username)
    respond_to do |format|
      format.html { @qr_svg = qr_svg(@card_url) }
      format.vcf do
        send_data vcard, filename: "#{@member.username}.vcf", type: "text/vcard", disposition: "attachment"
      end
    end
  end

  def style
    head :forbidden and return unless user_signed_in? && current_user == @member

    style = params[:card_style].to_s
    @member.profile.update(card_style: style) if Profile::CARD_STYLES.include?(style)
    redirect_to card_path(@member.username), status: :see_other
  end

  private

  def set_member
    @member = User.active.includes(:profile).find_by!(username: params[:username])
  end

  # Private profiles: only the member, their connections and moderators.
  def visible?
    return true if @member.profile&.public_profile? != false || @owner
    return false unless user_signed_in?

    current_user.admin_or_moderator? || current_user.connection_with(@member)&.accepted?
  end

  def qr_svg(url)
    RQRCode::QRCode.new(url, level: :m).as_svg(color: "0b1110", shape_rendering: "crispEdges", module_size: 6,
                                               standalone: true, use_path: true, viewbox: true, svg_attributes: { class: "card-qr-svg", "aria-hidden" => "true" })
  end

  def vcard
    name = @member.display_name.presence || @member.username
    role = @member.experiences.find(&:current?)
    esc = ->(text) { text.to_s.gsub(/([\;,])/) { "\\#{Regexp.last_match(1)}" }.gsub(/\r?\n/, "\\n") }
    lines = [ "BEGIN:VCARD", "VERSION:3.0", "FN:#{esc.call(name)}", "N:#{esc.call(name)};;;;" ]
    lines << "TITLE:#{esc.call(role.title)}" if role
    lines << "ORG:#{esc.call(role.organization)}" if role
    lines << "NOTE:#{esc.call(@member.professional_headline)}" if @member.professional_headline.present?
    lines << "URL:#{@card_url}"
    lines << "END:VCARD"
    lines.join("\r\n") + "\r\n"
  end
end
