class Admin::ScholarshipsController < Admin::BaseController
  before_action :set_record, only: [ :show, :edit, :update, :push ]

  def index
    @records = ScholarshipRecord.includes(:source).recently_scraped
    @records = @records.pending_push if params[:filter] == "pending"
    @pending_total = ScholarshipRecord.pending_push.count
  end

  def show
  end

  def edit
  end

  def update
    if @record.update(record_params)
      redirect_to admin_scholarship_path(@record),
        notice: "Guardado. Pulsa «Enviar a owl-api» para sincronizar el cambio."
    else
      flash.now[:alert] = @record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # Re-ingest the current state into owl-api (re-chunk + re-embed).
  def push
    @record.push_to_owl_api!
    redirect_to admin_scholarship_path(@record), notice: "Enviado a owl-api (#{@record.last_push_status})."
  rescue OwlApiClient::Error => e
    redirect_to admin_scholarship_path(@record), alert: "owl-api rechazó el envío: #{e.message}"
  end

  private

  def set_record
    @record = ScholarshipRecord.find(params[:id])
  end

  def record_params
    permitted = params.require(:scholarship_record).permit(
      *(ScholarshipRecord::EDITABLE_ATTRIBUTES - %w[fields levels]),
      :fields_text, :levels_text
    )
    permitted[:fields] = split_list(permitted.delete(:fields_text)) if permitted.key?(:fields_text)
    permitted[:levels] = split_list(permitted.delete(:levels_text)) if permitted.key?(:levels_text)
    permitted
  end

  def split_list(value)
    value.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end
end
