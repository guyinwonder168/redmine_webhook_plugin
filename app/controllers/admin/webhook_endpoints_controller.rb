class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy, :toggle, :test]

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
  end

  def new
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    load_form_collections
  end

  def create
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(endpoint_params)
    apply_form_config(@endpoint)

    if @endpoint.save
      set_api_key_warning(@endpoint)
      flash[:notice] = l(:notice_webhook_endpoint_created)
      redirect_to admin_webhook_endpoints_path
    else
      load_form_collections
      render :new
    end
  end

  def edit
    load_form_collections
  end

  def update
    @endpoint.assign_attributes(endpoint_params)
    apply_form_config(@endpoint)

    if @endpoint.save
      flash[:notice] = l(:notice_webhook_endpoint_updated)
      redirect_to admin_webhook_endpoints_path
    else
      load_form_collections
      render :edit
    end
  end

  def destroy
    affected = @endpoint.deliveries.update_all(
      status: RedmineWebhookPlugin::Webhook::Delivery::ENDPOINT_DELETED,
      endpoint_id: nil
    )

    @endpoint.destroy
    flash[:notice] = l(:notice_webhook_endpoint_deleted, count: affected)
    redirect_to admin_webhook_endpoints_path
  end

  def toggle
    @endpoint.toggle!(:enabled)
    flash[:notice] = l(:notice_webhook_endpoint_toggled)
    redirect_to admin_webhook_endpoints_path
  end

  def test
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: @endpoint.id,
      endpoint_url: @endpoint.url,
      event_id: SecureRandom.uuid,
      event_type: "test",
      action: "test",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      is_test: true,
      webhook_user_id: @endpoint.webhook_user_id
    )
    flash[:notice] = l(:notice_webhook_test_queued)
    redirect_to admin_webhook_endpoints_path
  end

  private

  def find_endpoint
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find(params[:id])
  end

  def load_form_collections
    @users = User.active.order(:lastname, :firstname)
    @projects = Project.active.order(:name)
  end

  def apply_form_config(endpoint)
    project_ids = Array(params[:webhook_endpoint][:project_ids]).reject(&:blank?).map(&:to_i)
    endpoint.project_ids_array = project_ids
    endpoint.events_config = extract_events_config(params[:events])
    endpoint.retry_config = extract_retry_config(params[:retry])
  end

  def extract_events_config(events_param)
    return {} if events_param.nil?

    events_param.to_unsafe_h.each_with_object({}) do |(resource, actions), memo|
      memo[resource.to_s] = {}
      actions.each do |action, value|
        memo[resource.to_s][action.to_s] = value.to_s == "1"
      end
    end
  end

  def extract_retry_config(retry_param)
    return {} if retry_param.nil?

    {
      "max_attempts" => retry_param[:max_attempts].to_i,
      "base_delay" => retry_param[:base_delay].to_i,
      "max_delay" => retry_param[:max_delay].to_i
    }
  end

  def endpoint_params
    params.require(:webhook_endpoint).permit(
      :name, :url, :enabled, :payload_mode, :webhook_user_id,
      :timeout, :ssl_verify,
      project_ids: []
    )
  end

  def set_api_key_warning(endpoint)
    return if endpoint.webhook_user_id.blank?

    token = Token.find_by(user_id: endpoint.webhook_user_id, action: "api")
    flash[:warning] = l(:warning_webhook_user_no_api_key) if token.nil?
  end
end
