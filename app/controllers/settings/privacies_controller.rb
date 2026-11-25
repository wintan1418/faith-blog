# frozen_string_literal: true

module Settings
  class PrivaciesController < ApplicationController
    before_action :authenticate_user!

    def edit
      @profile = current_user.profile
      load_contact_privacy
      # Seeing the controls is the answer to "Your contact details are now private".
      current_user.update_column(:contact_privacy_notice_pending, false) if current_user.contact_privacy_notice_pending?
    end

    def update
      @profile = current_user.profile
      if user_privacy_params.key?(:show_online_status)
        current_user.update_column(:show_online_status, ActiveModel::Type::Boolean.new.cast(user_privacy_params[:show_online_status]) == true)
      end

      if params.dig(:bible, :show_streak).present?
        BibleHabit.for(current_user).update!(show_streak: ActiveModel::Type::Boolean.new.cast(params.dig(:bible, :show_streak)) == true)
      end

      BrethrenCard.apply_visibility(current_user, contact_params)

      if @profile.update(privacy_params)
        redirect_to edit_settings_privacy_path, notice: "Privacy settings updated."
      else
        load_contact_privacy
        render :edit, status: :unprocessable_entity
      end
    end

    # "Not now" on the one-time notice.
    def dismiss_contact_notice
      current_user.update_column(:contact_privacy_notice_pending, false)
      respond_to do |format|
        format.html { redirect_back fallback_location: feed_path }
        format.turbo_stream { render turbo_stream: turbo_stream.remove("contact_privacy_notice") }
      end
    end

    private

    def load_contact_privacy
      @brethren_card = current_user.brethren_card || current_user.build_brethren_card
      @contact_shares = current_user.contact_shares.includes(viewer: { profile: { avatar_attachment: :blob } }).order(created_at: :desc)
      chosen_ids = @contact_shares.map(&:viewer_id)
      @connection_ids = current_user.connection_ids.to_set
      @shareable_connections = User.active.where(id: @connection_ids.to_a - chosen_ids).order(:username)
    end

    def privacy_params
      optional_params(:profile).permit(:public_profile)
    end

    def contact_params
      optional_params(:brethren_card).permit(:email_visibility, :whatsapp_visibility)
    end

    # "Show when I'm online" lives on the user, not the profile.
    def user_privacy_params
      @user_privacy_params ||= optional_params(:user).permit(:show_online_status)
    end
  end
end
