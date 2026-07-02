class ApplicationController < ActionController::Base
  include Authentication
  # Restore Current.session also on public pages (allow_unauthenticated_access
  # skips require_authentication, which is what normally resumes it).
  before_action :resume_session
  # Serve each request in the browser's preferred language (en/es).
  around_action :switch_locale
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def switch_locale(&action)
    I18n.with_locale(preferred_locale, &action)
  end

  # Best Accept-Language match among the app's locales, by q-value. Region
  # subtags collapse to their language ("es-MX" → :es).
  def preferred_locale
    candidates = request.headers["Accept-Language"].to_s.split(",").filter_map do |entry|
      tag, q = entry.split(";q=").map(&:strip)
      [ tag.to_s.split("-").first.to_s.downcase.to_sym, (q || "1").to_f ] if tag.present?
    end
    candidates.sort_by { |_, q| -q }.map(&:first)
      .find { |locale| I18n.available_locales.include?(locale) } || I18n.default_locale
  end
end
