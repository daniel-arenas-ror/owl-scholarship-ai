class PagesController < ApplicationController
  def home
    @owl_api_url = ENV.fetch("OWL_API_URL", "http://localhost:8000")
  end
end
