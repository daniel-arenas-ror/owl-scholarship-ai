# Allow owl-web to call owl-admin from the browser.
# OWL_WEB_ORIGINS is a comma-separated allow-list; defaults to the Vite dev server.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(ENV.fetch("OWL_WEB_ORIGINS", "http://localhost:5173").split(","))

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: false
  end
end
