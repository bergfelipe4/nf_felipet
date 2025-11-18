class ApplicationController < ActionController::Base
   before_action :configure_permitted_parameters, if: :devise_controller?
    def not_found
      flash[:alert] = "Página não existe"
  
      if user_signed_in?
        redirect_to authenticated_root_path
      else
        redirect_to unauthenticated_root_path
      end
    end

     def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:cpf])
    devise_parameter_sanitizer.permit(:account_update, keys: [:cpf])
  end
  
  end
  