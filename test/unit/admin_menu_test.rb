require File.expand_path("../test_helper", __dir__)

class AdminMenuTest < ActiveSupport::TestCase
  test "admin menu includes webhooks item" do
    items = Redmine::MenuManager.items(:admin_menu).map(&:name)
    assert_includes items, :webhooks
  end
end
