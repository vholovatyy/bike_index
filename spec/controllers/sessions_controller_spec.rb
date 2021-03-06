require "spec_helper"

describe SessionsController do
  describe "new" do
    it "renders and calls store_return_to" do
      expect(controller).to receive(:store_return_to)
      get :new
      expect(response.code).to eq("200")
      expect(response).to render_template("new")
      expect(flash).to_not be_present
      expect(response).to render_with_layout("application_revised")
    end
    context "signed in user" do
      include_context :logged_in_as_user
      it "redirects" do
        get :new, return_to: "/bikes/12?contact_owner=true"
        expect(response).to redirect_to "/bikes/12?contact_owner=true"
      end
      context "unconfirmed" do
        let(:user) { FactoryBot.create(:user) }
        it "redirects to please_confirm_email" do
          user.reload
          expect(user.confirmed?).to be_falsey
          get :new, return_to: "/bikes/12?contact_owner=true"
          expect(response).to redirect_to please_confirm_email_users_path
          expect(session[:return_to]).to eq "/bikes/12?contact_owner=true"
        end
      end
    end
    context "setting return_to" do
      it "actually sets it" do
        get :new, return_to: "/bikes/12?contact_owner=true"
        expect(session[:return_to]).to eq "/bikes/12?contact_owner=true"
      end
      context "with partner" do
        it "actually sets it, renders bikehub layout" do
          get :new, return_to: "/bikes/12?contact_owner=true", partner: "bikehub"
          expect(session[:return_to]).to eq "/bikes/12?contact_owner=true"
          expect(response).to render_with_layout("application_revised_bikehub")
        end
        context "partner in session" do
          it "actually sets it, renders bikehub layout" do
            session[:partner] = "bikehub"
            get :new, return_to: "/bikes/12?contact_owner=true"
            expect(response).to render_with_layout("application_revised_bikehub")
            expect(session[:partner]).to be_nil
          end
        end
      end
    end
  end

  describe "destroy" do
    include_context :logged_in_as_user
    it "logs out the current user" do
      session[:return_to] = "/bikes/12?contact_owner=true"
      session[:partner] = "bikehub"
      session[:passive_organization_id] = 12
      session[:whatever] = "XXXXXX"
      get :destroy
      expect(cookies.signed[:auth]).to be_nil
      expect(session[:user_id]).to be_nil
      expect(response).to redirect_to goodbye_url
      expect(flash[:notice]).to be_present
      expect(session[:return_to]).to be_nil
      expect(session[:partner]).to be_nil
      expect(session[:passive_organization_id]).to be_nil
      expect(session[:whatever]).to be_nil
    end
    context "unconfirmed user" do
      let(:user) { FactoryBot.create(:user) }
      it "logs out the user" do
        get :destroy
        expect(cookies.signed[:auth]).to be_nil
        expect(session[:user_id]).to be_nil
        expect(response).to redirect_to goodbye_url
      end
    end
  end

  describe "create" do
    let(:user) { FactoryBot.create(:user_confirmed) }
    describe "when user is found" do
      before do
        expect(User).to receive(:fuzzy_email_find).and_return(user)
      end

      describe "when authentication works" do
        it "authenticates and removes partner session" do
          session[:partner] = "bikehub"
          expect(user).to receive(:authenticate).and_return(true)
          request.env["HTTP_REFERER"] = user_home_url
          post :create, session: { password: "would be correct" }
          expect(cookies.signed[:auth][1]).to eq(user.auth_token)
          expect(response).to redirect_to "https://new.bikehub.com/account"
          expect(session[:partner]).to be_nil
        end

        context "admin" do
          let(:user) { FactoryBot.create(:admin) }
          it "authenticates and redirects to admin" do
            expect(user).to receive(:authenticate).and_return(true)
            request.env["HTTP_REFERER"] = user_home_url
            post :create, session: { password: "would be correct" }
            expect(cookies.signed[:auth][1]).to eq(user.auth_token)
            expect(response).to redirect_to admin_root_url
          end
        end

        it "redirects to discourse_authentication url if it's a valid oauth url" do
          expect(user).to receive(:authenticate).and_return(true)
          session[:discourse_redirect] = "sso=foo&sig=bar"
          post :create, session: { hmmm: "yeah" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(response).to redirect_to discourse_authentication_url
        end

        it "redirects to return_to if it's a valid oauth url" do
          expect(user).to receive(:authenticate).and_return(true)
          session[:return_to] = oauth_authorization_url(cool_thing: true)
          post :create, session: { stuff: "lololol" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(session[:return_to]).to be_nil
          expect(response).to redirect_to oauth_authorization_url(cool_thing: true)
        end

        it "redirects to facebook.com/bikeindex" do
          expect(user).to receive(:authenticate).and_return(true)
          session[:return_to] = "https://facebook.com/bikeindex"
          post :create, session: { thing: "asdfasdf" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(session[:return_to]).to be_nil
          expect(response).to redirect_to "https://facebook.com/bikeindex"
        end

        it "does not redirect to a random facebook page" do
          expect(user).to receive(:authenticate).and_return(true)
          session[:return_to] = "https://facebook.com/bikeindex-mean-place"
          post :create, session: { thing: "asdfasdf" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(session[:return_to]).to be_nil
          expect(response).to redirect_to user_home_url
        end

        it "doesn't redirect and clears the session if not a valid oauth url" do
          expect(user).to receive(:authenticate).and_return(true)
          session[:return_to] = "http://testhost.com/bad_place?f=#{oauth_authorization_url(cool_thing: true)}"
          post :create, session: { thing: "asdfasdf" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(session[:return_to]).to be_nil
          expect(response).to redirect_to user_home_url
        end
      end

      it "does not authenticate the user when user authentication fails" do
        expect(user).to receive(:authenticate).and_return(false)
        post :create, session: { password: "something incorrect" }
        expect(session[:user_id]).to be_nil
        expect(response).to render_template("new")
        expect(response).to render_with_layout("application_revised")
      end
      context "user is organization admin" do
        let(:organization) { FactoryBot.create(:organization, kind: organization_kind) }
        let(:user) { FactoryBot.create(:organization_member, organization: organization) }
        let(:organization_kind) { "bike_shop" }
        it "signs in" do
          expect(user).to receive(:authenticate).and_return(true)
          request.env["HTTP_REFERER"] = user_home_url
          post :create, session: { password: "would be correct" }
          expect(cookies.signed[:auth][1]).to eq(user.auth_token)
          expect(session[:render_donation_request]).to be_falsey
          expect(response).to redirect_to organization_bikes_path(organization_id: organization.to_param)
        end
        context "organization is police" do
          let(:organization_kind) { "law_enforcement" }
          it "sets flash of render_donation_request" do
            expect(user).to receive(:authenticate).and_return(true)
            request.env["HTTP_REFERER"] = user_home_url
            post :create, session: { password: "would be correct" }
            expect(cookies.signed[:auth][1]).to eq(user.auth_token)
            expect(session[:render_donation_request]).to eq "law_enforcement"
            expect(response).to redirect_to organization_bikes_path(organization_id: organization.to_param)
          end
        end
      end
    end

    context "unconfirmed" do
      let(:user) { FactoryBot.create(:user) }
      it "logs in, sends to please_confirm_email" do
        expect(user.authenticate("testthisthing7$")).to be_truthy
        post :create, session: { email: user.email, password: "testthisthing7$" }
        expect(User.from_auth(cookies.signed[:auth])).to eq(user)
        expect(response).to redirect_to(please_confirm_email_users_path)
      end
      context "with confirmed user_email" do
        let!(:user_email) { FactoryBot.create(:user_email, user: user) }
        it "logs in, sends to please_confirm_email" do
          expect(user_email.confirmed).to be_truthy
          post :create, session: { email: user.email, password: "testthisthing7$" }
          expect(User.from_auth(cookies.signed[:auth])).to eq(user)
          expect(response).to redirect_to(please_confirm_email_users_path)
        end
      end
    end

    it "does not log in the user when the user is not found" do
      post :create, session: { email: "notThere@example.com" }
      expect(cookies.signed[:auth]).to be_nil
      expect(response).to render_template(:new)
      expect(response).to render_with_layout("application_revised")
    end
  end
end
