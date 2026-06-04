# frozen_string_literal: true

RSpec.describe PoliPage::Client do
  let(:api_key) { "pp_test_abc" }

  describe "on_request constructor kwarg" do
    it "accepts on_request: as a callable and exposes it via instance config" do
      hook = ->(_e) {}
      expect { described_class.new(api_key: api_key, on_request: hook) }.not_to raise_error
    end

    it "tolerates nil on_request (default)" do
      expect { described_class.new(api_key: api_key) }.not_to raise_error
    end
  end
end
