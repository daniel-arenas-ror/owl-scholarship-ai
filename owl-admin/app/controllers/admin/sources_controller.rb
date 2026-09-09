class Admin::SourcesController < Admin::BaseController
  def index
    @sources = Source.order(:name)
    @record_counts = Scholarship.group(:source).count # { host => n }
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
