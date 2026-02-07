class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  def index
    deliveries = RedmineWebhookPlugin::Webhook::Delivery.order(created_at: :desc)
    deliveries = deliveries.where(endpoint_id: params[:endpoint_id]) if params[:endpoint_id].present?
    deliveries = deliveries.where(event_type: params[:event_type]) if params[:event_type].present?
    deliveries = deliveries.where(status: params[:status]) if params[:status].present?
    deliveries = deliveries.where(event_id: params[:event_id]) if params[:event_id].present?

    respond_to do |format|
      format.html do
        @delivery_pages, @deliveries = paginate(deliveries, per_page: 50)
      end
      format.csv do
        export_to_csv(deliveries)
      end
    end
  end

  def show
    @delivery = RedmineWebhookPlugin::Webhook::Delivery.find(params[:id])
  end

  def replay
    @delivery = RedmineWebhookPlugin::Webhook::Delivery.find(params[:id])
    @delivery.reset_for_replay!

    # Enqueue delivery job if using ActiveJob execution mode
    if RedmineWebhookPlugin::Webhook::ExecutionMode.detect == :activejob
      RedmineWebhookPlugin::Webhook::DeliveryJob.perform_later(@delivery.id)
    end

    flash[:notice] = "Webhook delivery has been queued for replay."
    redirect_to admin_webhook_delivery_path(@delivery)
  end

  def bulk_replay
    delivery_ids = params[:ids]

    if delivery_ids.blank? || delivery_ids.empty?
      flash[:warning] = "No deliveries selected."
      redirect_to admin_webhook_deliveries_path
      return
    end

    deliveries = RedmineWebhookPlugin::Webhook::Delivery.where(id: delivery_ids)
    replayed_count = 0

    deliveries.each do |delivery|
      delivery.reset_for_replay!

      # Enqueue delivery job if using ActiveJob execution mode
      if RedmineWebhookPlugin::Webhook::ExecutionMode.detect == :activejob
        RedmineWebhookPlugin::Webhook::DeliveryJob.perform_later(delivery.id)
      end

      replayed_count += 1
    end

    flash[:notice] = "#{replayed_count} deliveries queued for replay."
    redirect_to admin_webhook_deliveries_path
  end

  private

  def export_to_csv(deliveries)
    # Limit to 1000 most recent records to prevent memory issues
    deliveries_to_export = deliveries.limit(1000)

    csv_data = CSV.generate(headers: true) do |csv|
      # Add header row
      csv << ["ID", "Endpoint", "Event Type", "Action", "Status", "HTTP Status", "Created At"]

      # Add data rows
      deliveries_to_export.each do |delivery|
        endpoint_name = delivery.endpoint&.name || ""
        csv << [
          delivery.id,
          endpoint_name,
          delivery.event_type,
          delivery.action,
          delivery.status,
          delivery.http_status || "",
          format_time(delivery.created_at)
        ]
      end
    end

    send_data(
      csv_data,
      type: "text/csv; header=present",
      filename: "webhook_deliveries.csv"
    )
  end
end
