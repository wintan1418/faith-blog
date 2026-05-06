class BackfillUserRiskProfiles < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    User.find_each(batch_size: 500) do |user|
      next if user.risk_profile

      user.create_risk_profile!(risk_level: :clear, risk_score: 0.0)
    end
  end

  def down
    UserRiskProfile.delete_all
  end
end
