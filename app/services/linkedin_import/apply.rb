# frozen_string_literal: true

module LinkedinImport
  # Saves the items a member ticked on the review page. Each item comes back
  # from the form as JSON, so it's cleaned again here, and anything already on
  # the profile (same role at the same place, same school, same name) is skipped.
  class Apply
    Counts = Struct.new(:roles, :schools, :certifications, :languages, :skills, :details, keyword_init: true) do
      def total = to_h.values.sum

      def sentence
        words = { roles: "role", schools: "school", certifications: "certification", languages: "language",
                  skills: "skill", details: "profile detail" }
        words.filter_map { |key, word| "#{self[key]} #{word.pluralize(self[key])}" if self[key].positive? }.to_sentence
      end
    end

    def initialize(user, params)
      @user = user
      @params = params
      @counts = Counts.new(roles: 0, schools: 0, certifications: 0, languages: 0, skills: 0, details: 0)
    end

    def call
      ActiveRecord::Base.transaction do
        apply_details
        apply_positions
        apply_educations
        apply_certifications
        apply_languages
        apply_skills
      end
      @counts
    end

    private

    def items(key)
      Array(@params[key]).first(LIMITS.fetch(key.to_sym, 30)).filter_map do |json|
        value = JSON.parse(json.to_s)
        value.is_a?(Hash) ? value : nil
      rescue JSON::ParserError
        nil
      end
    end

    def profile = @user.profile || @user.create_profile!

    def apply_details
      changes = {}
      changes[:headline] = Clean.text(@params[:headline], 120) if @params[:use_headline] == "1"
      changes[:bio] = Clean.paragraph(@params[:summary], 500) if @params[:use_summary] == "1"
      changes[:industry] = Clean.text(@params[:industry], 80) if @params[:use_industry] == "1"
      changes[:location] = Clean.text(@params[:location], 100) if @params[:use_location] == "1"
      changes.compact!
      return if changes.empty?

      profile.update!(changes)
      @counts.details += changes.size
    end

    def apply_positions
      existing = @user.experiences.pluck(:title, :organization).to_set { |t, o| [ MatchKey.for(t), MatchKey.for(o) ] }
      items("positions").each do |p|
        role = Clean.position(title: p["title"], organization: p["organization"], location: p["location"],
                              description: p["description"], start_on: Clean.month(p["start_on"]),
                              end_on: Clean.month(p["end_on"]), current: [ true, "true" ].include?(p["current"]),
                              employment_type: p["employment_type"])
        next unless role

        key = [ MatchKey.for(role["title"]), MatchKey.for(role["organization"]) ]
        next if existing.include?(key)
        next unless @user.experiences.new(role).save

        existing << key
        @counts.roles += 1
      end
    end

    def apply_educations
      existing = @user.educations.pluck(:school).to_set(&:downcase)
      items("educations").each do |e|
        school = Clean.education(school: e["school"], qualification: e["qualification"], field_of_study: e["field_of_study"],
                                 start_year: e["start_year"], end_year: e["end_year"])
        next if school.nil? || existing.include?(school["school"].downcase)
        next unless @user.educations.new(school).save

        existing << school["school"].downcase
        @counts.schools += 1
      end
    end

    def apply_certifications
      existing = @user.certifications.pluck(:name).to_set(&:downcase)
      items("certifications").each do |c|
        cert = Clean.certification(name: c["name"], issuer: c["issuer"], issued_on: Clean.month(c["issued_on"]),
                                   expires_on: Clean.month(c["expires_on"]), credential_url: c["credential_url"])
        next if cert.nil? || existing.include?(cert["name"].downcase)
        next unless @user.certifications.new(cert).save

        existing << cert["name"].downcase
        @counts.certifications += 1
      end
    end

    def apply_languages
      existing = @user.languages.pluck(:name).to_set(&:downcase)
      items("languages").each do |l|
        lang = Clean.language(name: l["name"], proficiency: l["proficiency"])
        next if lang.nil? || existing.include?(lang["name"].downcase)
        next unless @user.languages.new(lang).save

        existing << lang["name"].downcase
        @counts.languages += 1
      end
    end

    def apply_skills
      picked = Clean.skills(@params[:skills])
      return if picked.empty?

      before = profile.skills.size
      profile.update!(skills_list: (profile.skills + picked).join(", "))
      @counts.skills += profile.skills.size - before
    end
  end
end
