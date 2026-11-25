# frozen_string_literal: true

# "Share my contact" (from a profile, a chat or Settings → Privacy) puts a
# connection on the member's "Connections I choose" list; "Stop sharing" takes them off.
class ContactSharesController < ApplicationController
  before_action :authenticate_user!

  def create
    person = find_person
    return redirect_back(fallback_location: edit_settings_privacy_path, alert: "We couldn't find that member.") unless person

    card = current_user.brethren_card || current_user.create_brethren_card
    unless card.has_contact?
      return redirect_to edit_settings_brethren_card_path(anchor: "contact"),
                         alert: "Add your email or WhatsApp number to your Brethren Card first, then share it."
    end

    share = current_user.contact_shares.find_or_initialize_by(viewer: person)
    if share.persisted? || share.save
      card.open_to_chosen!
      redirect_back fallback_location: user_path(person.username),
                    notice: "#{person.display_name} can now see your #{shared_words(card)}."
    else
      redirect_back fallback_location: user_path(person.username), alert: share.errors.full_messages.to_sentence
    end
  end

  def destroy
    share = current_user.contact_shares.includes(:viewer).find_by(id: params[:id])
    return redirect_back(fallback_location: edit_settings_privacy_path, alert: "That was already removed.") unless share

    share.destroy
    redirect_back fallback_location: edit_settings_privacy_path,
                  notice: "You stopped sharing your contact details with #{share.viewer.display_name}."
  end

  private

  # By id (the buttons) or @username (the add box in Settings).
  def find_person
    scope = User.active
    if params[:user_id].present?
      scope.find_by(id: params[:user_id].to_s)
    elsif params[:username].present?
      scope.find_by("lower(username) = ?", params[:username].to_s.strip.delete_prefix("@").downcase)
    end
  end

  def shared_words(card)
    fields = []
    fields << "email" if card.email.present? && !card.email_visibility_only_me?
    fields << "WhatsApp number" if card.whatsapp_number.present? && !card.whatsapp_visibility_only_me?
    fields.any? ? fields.to_sentence : "contact details"
  end
end
