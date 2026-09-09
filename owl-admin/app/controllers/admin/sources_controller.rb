class Admin::SourcesController < Admin::BaseController
  def index
    @sources = Source
      .left_joins(:scholarship_records)
      .select("sources.*, COUNT(scholarship_records.id) AS records_count")
      .group("sources.id")
      .order("sources.name")
  end

  def update
    @source = Source.find(params[:id])
    if @source.update(source_params)
      redirect_to admin_sources_path, notice: "Fuente actualizada."
    else
      redirect_to admin_sources_path, alert: @source.errors.full_messages.to_sentence
    end
  end

  private

  def source_params
    params.require(:source).permit(:name, :enabled)
  end
end
