class ApplicationController < ActionController::Base
  include Pagy::Backend

  before_action :configure_permitted_parameters, if: :devise_controller?

  def not_found
    flash[:alert] = "Página não existe"

    if user_signed_in?
      redirect_to authenticated_root_path
    else
      redirect_to unauthenticated_root_path
    end
  end

  protected

  def configure_permitted_parameters
  extra_keys = [
    :cpf, :cnpj, :razao_social, :nome_fantasia,
    :telefone, :inscricao_estadual,
    :rua, :numero, :complemento,
    :bairro, :municipio, :cep
  ]

  devise_parameter_sanitizer.permit(:sign_up, keys: extra_keys)
  devise_parameter_sanitizer.permit(:account_update, keys: extra_keys)
end

end
