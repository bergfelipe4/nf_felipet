class ApplicationController < ActionController::Base
    def not_found
      flash[:alert] = "Página não existe"
  
      if user_signed_in?
        redirect_to authenticated_root_path
      else
        redirect_to unauthenticated_root_path
      end
    end
  end
  