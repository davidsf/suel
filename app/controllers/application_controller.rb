class ApplicationController < ActionController::Base
  include Authentication
  # Restore Current.session also on public pages (allow_unauthenticated_access
  # skips require_authentication, which is what normally resumes it).
  before_action :resume_session
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
