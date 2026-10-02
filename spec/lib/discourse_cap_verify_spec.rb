# frozen_string_literal: true

RSpec.describe DiscourseCap::Verify do
  before do
    SiteSetting.cap_verification_enabled = true
    SiteSetting.cap_verification_instance_url = "https://cap.example.com"
    SiteSetting.cap_verification_site_key = "sk_test"
    SiteSetting.cap_verification_secret_key = "secret_test"
    SiteSetting.cap_verification_protect_signup = true
    SiteSetting.cap_verification_skip_for_staff = true
    SiteSetting.cap_verification_min_trust_level = 0
  end

  def stub_siteverify(success:)
    stub_request(:post, "https://cap.example.com/sk_test/siteverify").to_return(
      status: 200,
      body: { success: success }.to_json,
      headers: {
        "Content-Type" => "application/json",
      },
    )
  end

  describe ".enforce!" do
    it "passes when the Cap server accepts the token" do
      stub_siteverify(success: true)

      expect(
        described_class.enforce!(
          token: "good-token",
          remote_ip: "1.2.3.4",
          context: "signup",
        ),
      ).to eq(true)
    end

    it "raises invalid_token when the Cap server rejects it" do
      stub_siteverify(success: false)

      expect {
        described_class.enforce!(
          token: "bad-token",
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:invalid_token)
      }
    end

    it "raises missing_token when no token is submitted" do
      expect {
        described_class.enforce!(
          token: nil,
          remote_ip: "1.2.3.4",
          context: "signup",
        )
      }.to raise_error(DiscourseCap::Verify::Failure) { |e|
        expect(e.reason).to eq(:missing_token)
      }
    end

    it "is a no-op when the plugin is disabled" do
      SiteSetting.cap_verification_enabled = false

      expect(
        described_class.enforce!(
          token: nil,
          remote_ip: "1.2.3.4",
          context: "signup",
        ),
      ).to eq(true)
    end

    it "exempts staff" do
      staff = Fabricate(:admin)

      expect(
        described_class.enforce!(
          token: nil,
          remote_ip: "1.2.3.4",
          context: "login",
          actor: staff,
        ),
      ).to eq(true)
    end

    it "exempts users at or above the configured trust level" do
      SiteSetting.cap_verification_min_trust_level = 2
      user = Fabricate(:user, trust_level: TrustLevel[2])

      expect(
        described_class.enforce!(
          token: nil,
          remote_ip: "1.2.3.4",
          context: "login",
          actor: user,
        ),
      ).to eq(true)
    end
  end
end
