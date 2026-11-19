# frozen_string_literal: true

require "test_helper"
require "zip"
require "minitest/mock"

class LinkedinImportTest < ActiveSupport::TestCase
  # A data export like LinkedIn's: a few CSVs, one with "Notes:" lines on top.
  def export_zip(files)
    path = Rails.root.join("tmp", "linkedin-#{SecureRandom.hex(4)}.zip").to_s
    Zip::File.open(path, create: true) do |zip|
      files.each { |name, body| zip.get_output_stream(name) { |io| io.write(body) } }
    end
    path
  end

  def upload(path) = Rack::Test::UploadedFile.new(path, "application/zip")

  EXPORT = {
    "Profile.csv" => "First Name,Last Name,Maiden Name,Address,Birth Date,Headline,Summary,Industry,Zip Code,Geo Location\n" \
                     "Ada,Okafor,,,,Product Designer at Lumen,\"I design money tools.\nMentor to designers.\",Software Development,,\"Lagos, Nigeria\"\n",
    "Positions.csv" => "Company Name,Title,Description,Location,Started On,Finished On\n" \
                       "Lumen Fintech,Product Designer,Leads the app design.,Lagos,Mar 2023,\n" \
                       "Hope Studio,UI Designer,,Remote,Jan 2020,Feb 2023\n",
    "Education.csv" => "School Name,Start Date,End Date,Notes,Degree Name,Activities\n" \
                       "University of Lagos,2012,2016,,\"Bachelor of Science - BSc, Computer Science\",\n",
    "Skills.csv" => "Name\nUX design\nFigma\nux design\n",
    "Certifications.csv" => "Name,Url,Authority,Started On,Finished On,License Number\n" \
                            "Google UX Design Certificate,https://coursera.org/verify/ABC,Google,Jun 2022,,\n" \
                            "Bad Link Cert,javascript:alert(1),Nobody,,,\n",
    "Languages.csv" => "Name,Proficiency\nEnglish,Native or bilingual proficiency\nFrench,Elementary proficiency\n",
    "Connections.csv" => "Notes:\n\"When exporting your connection data...\"\n\nFirst Name,Last Name\nA,B\n"
  }.freeze

  test "reads a LinkedIn data export into a draft" do
    draft = LinkedinImport.read(upload(export_zip(EXPORT)))

    assert_equal "Product Designer at Lumen", draft.headline
    assert_equal "Software Development", draft.industry
    assert_equal "Lagos, Nigeria", draft.location
    assert_match(/Mentor to designers/, draft.summary)

    current, past = draft.positions
    assert_equal [ "Product Designer", "Lumen Fintech", true, "2023-03-01", nil ],
                 current.values_at("title", "organization", "current", "start_on", "end_on")
    assert_equal [ false, "2023-02-01" ], past.values_at("current", "end_on")

    school = draft.educations.sole
    assert_equal [ "University of Lagos", "Bachelor of Science - BSc", "Computer Science", 2012, 2016 ],
                 school.values_at("school", "qualification", "field_of_study", "start_year", "end_year")
    assert_equal [ "UX design", "Figma" ], draft.skills
    assert_equal [ "https://coursera.org/verify/ABC", nil ], draft.certifications.map { |c| c["credential_url"] }
    assert_equal %w[native elementary], draft.languages.map { |l| l["proficiency"] }
  end

  test "refuses files that aren't a LinkedIn PDF or export" do
    text = Rails.root.join("tmp", "not-linkedin.txt").to_s
    File.write(text, "hello")
    error = assert_raises(LinkedinImport::Error) { LinkedinImport.read(Rack::Test::UploadedFile.new(text, "text/plain")) }
    assert_match(/isn't a LinkedIn PDF or ZIP/, error.message)

    other = export_zip("photos/cat.csv" => "a,b\n1,2\n")
    assert_raises(LinkedinImport::Error) { LinkedinImport.read(upload(other)) }
  end

  # The PDF path with the AI step faked.
  class FakePdf < LinkedinImport::PdfReader
    def initialize(text, reply)
      super("unused.pdf")
      @text = text
      @reply = reply
    end

    private

    def extract_text = @text
    def ask_ai(_text) = { "content" => [ { "type" => "text", "text" => @reply } ] }
  end

  test "a profile PDF is sorted into sections by the AI, then cleaned" do
    reply = {
      headline: "Nurse at Korle Bu", summary: "", industry: "healthcare & medicine", location: "Accra",
      positions: [ { title: "Registered Nurse", company: "Korle Bu", start: "2019-05", end: nil, current: true, description: "" },
                   { title: "", company: "Missing title", start: "2018-01" } ],
      education: [ { school: "University of Ghana", degree: "BSc", field: "Nursing", start_year: 2014, end_year: 2018 } ],
      skills: [ "Triage", "Patient care" ],
      certifications: [ { name: "Registered Nurse licence", issuer: "Nursing and Midwifery Council", issued: "2019" } ],
      languages: [ { name: "Twi", proficiency: "Native or Bilingual" } ]
    }.to_json
    Ai::Moderation::Client.stub(:stub?, false) do
      draft = FakePdf.new("Contact www.linkedin.com Grace Mensah Nurse at Korle Bu Experience ...", reply).call
      assert_equal "Healthcare & Medicine", Profile.new(industry: draft.industry).industry
      assert_equal [ "Registered Nurse" ], draft.positions.map { |p| p["title"] } # the untitled role is dropped
      assert_equal "2019-01-01", draft.certifications.first["issued_on"]
      assert_equal "native", draft.languages.first["proficiency"]
    end
  end

  # LinkedIn's "Save to PDF" after the sidebar and main column are unmixed.
  PDF_TEXT = <<~TEXT
    Contact
    www.linkedin.com/in/adaokafor (LinkedIn)
    ada@example.com
    Top Skills
    UX Design
    Figma
    User Research
    Languages
    English (Native or Bilingual)
    Yoruba (Native or Bilingual)
    Certifications
    Google UX Design Certificate
    Ada Okafor
    Product Designer at Lumen Fintech
    Lagos, Lagos State, Nigeria
    Summary
    I design money tools that people in Lagos actually use.
    Experience
    Lumen Fintech
    3 years 2 months
    Senior Product Designer
    March 2024 - Present (1 year 9 months)
    Lagos, Nigeria
    Leads the design of the savings app.
    Product Designer
    March 2022 - March 2024 (2 years 1 month)
    Lagos, Nigeria
    Hope Studio
    UI Designer
    January 2020 - February 2022 (2 years 2 months)
    Remote
    Page 1 of 2
    Education
    University of Lagos
    Bachelor of Science - BSc, Computer Science · (2012 - 2016)
    Page 2 of 2
  TEXT

  test "without AI, the PDF is read by LinkedIn's layout" do
    draft = Ai::Moderation::Client.stub(:stub?, true) { FakePdf.new(PDF_TEXT, nil).call }
    assert_equal "Product Designer at Lumen Fintech", draft.headline
    assert_match "Lagos", draft.location
    assert_match "money tools", draft.summary
    roles = draft.positions.map { |p| [ p["title"], p["organization"], p["start_on"].to_s, p["current"] ] }
    assert_equal [ "Senior Product Designer", "Lumen Fintech", "2024-03-01", true ], roles[0]
    assert_equal [ "Product Designer", "Lumen Fintech", "2022-03-01", false ], roles[1]
    assert_equal [ "UI Designer", "Hope Studio", "2020-01-01", false ], roles[2]
    assert_equal "University of Lagos", draft.educations.first["school"]
    assert_equal [ 2012, 2016 ], [ draft.educations.first["start_year"], draft.educations.first["end_year"] ]
    assert_equal [ "UX Design", "Figma", "User Research" ], draft.skills
    assert_equal %w[English Yoruba], draft.languages.map { |l| l["name"] }
    assert_equal [ "Google UX Design Certificate" ], draft.certifications.map { |c| c["name"] }
  end

  test "when the AI is slow or unreachable, the layout reader takes over" do
    slow = Class.new(FakePdf) { def ask_ai(_text) = raise(Ai::Moderation::Client::ApiError, "openai unreachable: Net::ReadTimeout") }
    draft = Ai::Moderation::Client.stub(:stub?, false) { slow.new(PDF_TEXT, nil).call }
    assert_equal 3, draft.positions.size
    assert_equal "Product Designer at Lumen Fintech", draft.headline
  end

  test "a PDF reply that isn't JSON falls back to the layout reader" do
    draft = Ai::Moderation::Client.stub(:stub?, false) { FakePdf.new(PDF_TEXT, "Sorry, I can't").call }
    assert_equal "University of Lagos", draft.educations.first["school"]
  end

  test "the import asks the AI with a long wait and room for a whole profile" do
    seen = nil
    fake = ->(**kw) { seen = kw; { "content" => [ { "type" => "text", "text" => "{}" } ] } }
    Ai::Moderation::Client.stub(:call, fake) do
      LinkedinImport::PdfReader.new("unused.pdf").send(:ask_ai, "text")
    end
    assert_operator seen[:timeout], :>=, 30
    assert_operator seen[:max_tokens], :>=, 3000
  end

  test "the PDF's sidebar and main column are read one after the other" do
    page = [
      "                                     Grace Mensah",
      "Contact",
      "www.linkedin.com/in/grace           Registered Nurse at Korle Bu",
      "Top Skills                           Accra, Ghana",
      "Triage                               Summary",
      "Patient Care                         Paediatric nurse on the wards."
    ].join("\n")
    text = LinkedinImport::PdfReader.unmix_columns(page)
    left, right = text.split("\n\n", 2)
    assert_includes left, "Top Skills\nTriage\nPatient Care"
    assert_includes right, "Registered Nurse at Korle Bu\nAccra, Ghana\nSummary\nPaediatric nurse on the wards."
    assert_not_includes right, "Triage"
  end
end
