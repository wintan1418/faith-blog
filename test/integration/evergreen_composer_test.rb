# frozen_string_literal: true

require "test_helper"

# The Evergreen "New breath" composer: a four-way kind switch, option rows
# with switches, outline icons instead of emoji, and the same form fields.
class EvergreenComposerTest < ActionDispatch::IntegrationTest
  setup do
    @member = create_member("composer_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    sign_in @member
  end

  test "the pop-up composer has the Evergreen layout and keeps every field" do
    get feed_path
    assert_response :success

    assert_select "dialog.fc-composer-dialog" do
      assert_select "h2", text: "New breath"
      assert_select "a.eg-cmp-drafts-link[href=?]", drafts_path
      assert_select "button[aria-label=Close][data-action~='click->composer-modal#close']"

      assert_select "[role=radiogroup] button[role=radio]", count: 4
      %w[breath prayer verse thread].each do |mode|
        assert_select "button[role=radio][data-mode=?][data-action~='click->composer-mode#switch']", mode
      end
      assert_select "button[role=radio][aria-checked=true]", count: 1, text: "Breath"

      assert_select "input[type=hidden][name='post[kind]'][value=breath]"
      assert_select "input[type=hidden][name='post[prayer_status]'][value=not_a_prayer]"
      assert_select "select[name='post[room_id]']"
      assert_select "input[type=checkbox][role=switch][name='post[anonymous]']"
      assert_select "[data-controller~=schedule-field] input[type=checkbox][role=switch]:not([name])"
      assert_select "input[type=file][name='post[images][]']"
      assert_select "input[type=file][name='post[voice_note]']"
      assert_select "button[data-action~='click->composer-assistant#suggestScripture']", text: /Suggest scripture/
      assert_select "button[data-action~='click->composer-assistant#checkGentleness']", text: /Check tone/
      assert_select "button[data-action~='click->bible-drawer#open']"
      assert_select "button[data-action~='click->emoji-picker#toggle']"
      assert_select "button[type=submit][value=draft]", text: "Save draft"
      assert_select "button[type=submit][value=published][data-composer-mode-target~=submit]", text: /Breathe/
    end
  end

  test "the composer uses outline icons, not emoji" do
    get new_post_path
    form = css_select("form.fc-composer-form").first.to_html
    assert_no_match(/[🎙️📖🕊️⏱️🙏⚡]/, form)
  end

  test "a prayer posted from the composer is a prayer request" do
    assert_difference -> { @member.posts.count }, 1 do
      post posts_path, params: { post: { content: "Please pray for my mother's surgery on Thursday.",
                                         kind: "breath", prayer_status: "prayer_pending", status: "published" } }
    end
    assert @member.posts.order(:id).last.prayer_status_prayer_pending?
  end
end
