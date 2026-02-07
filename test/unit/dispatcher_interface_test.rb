require File.expand_path("../test_helper", __dir__)

class DispatcherInterfaceTest < ActiveSupport::TestCase
  test "dispatcher exposes dispatch interface" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Dispatcher, :dispatch
  end
end
