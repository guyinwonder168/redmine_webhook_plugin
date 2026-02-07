module RedmineWebhookPlugin
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, partial: "hooks/redmine_webhook_plugin/html_head"
  end
end
