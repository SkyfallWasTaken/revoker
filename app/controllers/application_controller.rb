class ApplicationController < ActionController::Base
include Pundit::Authorization

rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
rescue_from Norairrecord::RecordNotFoundError, with: :record_not_found

private

def user_not_authorized
  flash[:alert] = "You are not authorized to perform this action."
  redirect_back fallback_location: root_path
end

def record_not_found
  flash[:alert] = "The record you're looking for could not be found."
  redirect_to root_path
end
end
