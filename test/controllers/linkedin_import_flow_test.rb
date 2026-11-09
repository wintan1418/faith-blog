# frozen_string_literal: true

require "test_helper"
require "zip"

class LinkedinImportFlowTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_member("li_flow")
    sign_in @me
    @zip = Rails.root.join("tmp", "li-flow-#{SecureRandom.hex(3)}.zip").to_s
    Zip::File.open(@zip, create: true) do |zip|
      LinkedinImportTest::EXPORT.each { |name, body| zip.get_output_stream(name) { |io| io.write(body) } }
    end
  end

  test "upload, review, then add the picked items" do
    @me.experiences.create!(title: "UI Designer", organization: "Hope Studio", start_month: "2020-01", end_month: "2023-02")

    post settings_linkedin_import_path, params: { file: Rack::Test::UploadedFile.new(@zip, "application/zip") }
    assert_response :success
    assert_select "h1", text: /what we found/
    assert_select "input[name='import[positions][]']", count: 2
    assert_select "input[name='import[positions][]'][disabled]", count: 1 # Hope Studio is already there

    roles = css_select("input[name='import[positions][]']:not([disabled])").map { |i| i["value"] }
    post apply_settings_linkedin_import_path, params: { import: {
      headline: "Product Designer at Lumen", use_headline: "1", industry: "Software Development", use_industry: "1",
      positions: roles + [ "not json", { title: "<b>Hacker</b>" }.to_json ],
      educations: [ { school: "University of Lagos", start_year: 2012, end_year: 2016 }.to_json ],
      certifications: [ { name: "Google UX Design Certificate", issuer: "Google", issued_on: "2022-06-01" }.to_json ],
      languages: [ { name: "English", proficiency: "native" }.to_json ],
      skills: [ "UX design", "Figma" ]
    } }

    assert_redirected_to user_path(@me.username, tab: "professional")
    follow_redirect!
    assert_match(/Imported from LinkedIn: 1 role, 1 school, 1 certification, 1 language, 2 skills, and 2 profile details/, flash[:notice])

    @me.reload
    assert_equal [ "Product Designer", "UI Designer" ], @me.experiences.map(&:title)
    assert @me.experiences.find_by(title: "Product Designer").current?
    assert_equal "Product Designer at Lumen", @me.profile.headline
    assert_equal "Software Development", @me.profile.industry
    assert_equal [ "UX design", "Figma" ], @me.profile.skills
    assert_equal "native", @me.languages.sole.proficiency
    assert_select ".pro-card[aria-label='Licenses and certifications'] .pro-item-title", text: "Google UX Design Certificate"
  end

  test "a role saved without match keys still counts as already on the profile" do
    role = @me.experiences.create!(title: "Product Designer", organization: "Lumen Fintech", start_month: "2023-03", current: true)
    role.update_columns(title_key: nil, organization_key: nil) # like roles saved before the keys existed

    post settings_linkedin_import_path, params: { file: Rack::Test::UploadedFile.new(@zip, "application/zip") }
    assert_select "input[name='import[positions][]'][disabled]", count: 1

    post apply_settings_linkedin_import_path, params: { import: { positions: [
      { title: "Product Designer", organization: "Lumen Fintech", start_on: "2023-03-01", current: true }.to_json
    ] } }
    assert_equal 1, @me.experiences.count
  end

  test "a bad file shows the reason on the upload page" do
    txt = Rails.root.join("tmp", "nope.txt").to_s
    File.write(txt, "nope")
    post settings_linkedin_import_path, params: { file: Rack::Test::UploadedFile.new(txt, "text/plain") }
    assert_response :unprocessable_entity
    assert_match(/isn(&#39;|')t a LinkedIn PDF or ZIP/, response.body)
  end

  test "volunteer and church roles show under Volunteering, jobs under Experience" do
    @me.experiences.create!(title: "Engineer", organization: "Paystack", employment_type: "Full-time", start_month: "2022-01", current: true)
    @me.experiences.create!(title: "Choir director", organization: "Grace Assembly", employment_type: "Ministry", start_month: "2019-01", current: true)

    get user_path(@me.username, tab: "professional")
    assert_select ".pro-card[aria-label=Experience] .pro-item-title", text: "Engineer"
    assert_select ".pro-card[aria-label=Volunteering] .pro-item-title", text: "Choir director"
    assert_select ".pro-card[aria-label=Volunteering] .pro-item-sub", text: /Church or ministry service/
  end

  test "new roles default to Full-time, and languages and certifications can be added" do
    get new_settings_experience_path
    assert_select "select[name='experience[employment_type]'] option[selected]", text: "Full-time"

    post settings_languages_path, params: { user_language: { name: "Yoruba", proficiency: "native" } }
    assert_equal "Native or bilingual", @me.languages.sole.proficiency_label
    post settings_languages_path, params: { user_language: { name: "yoruba", proficiency: "elementary" } }
    assert_equal 1, @me.languages.count

    post settings_certifications_path, params: { certification: { name: "ICAN", issuer: "ICAN", issued_month: "2021-05", credential_url: "http://insecure" } }
    assert_response :unprocessable_entity
    post settings_certifications_path, params: { certification: { name: "ICAN", issuer: "ICAN", issued_month: "2021-05" } }
    assert_equal "Issued May 2021", @me.certifications.sole.dates
  end
end
