class Admin::ScholarshipsController < Admin::BaseController
  before_action :set_scholarship, only: [ :show, :edit, :update ]

  def index
    @scholarships = Scholarship.recent
  end

  def show
  end

  def edit
  end

  # Editing writes through owl-api's ingest endpoint (re-chunk + re-embed), not
  # straight to the table — so the row and its vectors never drift apart.
  def update
    @scholarship.assign_attributes(scholarship_params)

    unless @scholarship.valid?
      flash.now[:alert] = @scholarship.errors.full_messages.to_sentence
      return render(:edit, status: :unprocessable_entity)
    end

    result = OwlApiClient.ingest(@scholarship.to_ingest_payload)
    redirect_to admin_scholarship_path(@scholarship), notice: "Enviado a owl-api (#{result[:action]})."
  rescue OwlApiClient::Error => e
    flash.now[:alert] = "owl-api rechazó el cambio: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  private

  def set_scholarship
    @scholarship = Scholarship.find(params[:id])
  end

  def scholarship_params
    permitted = params.require(:scholarship).permit(
      *(Scholarship::EDITABLE_ATTRIBUTES - %w[fields levels]),
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
