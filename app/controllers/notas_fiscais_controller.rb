require "securerandom"

class NotasFiscaisController < ApplicationController
  before_action :authenticate_user!
  before_action :set_nota_fiscal, only: %i[edit update destroy]

require 'ostruct'
def index
  @cpf_consulta   = current_user.cpf
  @consulta_result = nil
  @consulta_error  = nil
  @notas_consulta  = []

  if @cpf_consulta.present?
    resposta = ApiCliente.consultar_notas(@cpf_consulta)

    if resposta[:success]
      @consulta_result = resposta[:body] || {}
      raw_notas        = Array(@consulta_result["notas"]) # array de hashes

      # normaliza chaves para strings (caso venham simbolizadas)
      @notas_consulta = raw_notas.map { |h| h.transform_keys(&:to_s) }

    else
      @consulta_error = resposta[:error] || "Não foi possível consultar as notas."
    end
  else
    @consulta_error = "Seu usuário ainda não possui CPF cadastrado."
  end

  # -----------------------
  # FILTRAGEM (substitui Ransack para coleções em memória)
  # Espera params[:q] = { "CHAVE_cont" => "...", "SERIE_eq" => "...", "CSTAT_eq" => "..." }
  # -----------------------
  q = params.fetch(:q, {}).to_unsafe_h

  notas_filtradas = @notas_consulta.select do |nota|
    ok = true

    # CHAVE_cont (contém)
    if v = q["CHAVE_cont"].presence
      ok &= nota["CHAVE"].to_s.downcase.include?(v.to_s.downcase)
    end

    # SERIE_eq (igual)
    if v = q["SERIE_eq"].presence
      ok &= nota["SERIE"].to_s == v.to_s
    end

    # CSTAT (exato) - aceita CSTAT_CONSULTA ou CSTAT_AUTORIZAR
    if v = q["CSTAT_eq"].presence
      cstat = (nota["CSTAT_CONSULTA"] || nota["CSTAT_AUTORIZAR"]).to_s
      ok &= cstat == v.to_s
    end

    # Data range opcional: DT_INI_gteq and DT_INI_lteq (formato ISO esperável)
    if v = q["DT_INI_gteq"].presence
      begin
        ok &= Time.zone.parse(nota["DT_INI"]).to_i >= Time.zone.parse(v).to_i
      rescue
        ok &= true
      end
    end
    if v = q["DT_INI_lteq"].presence
      begin
        ok &= Time.zone.parse(nota["DT_INI"]).to_i <= Time.zone.parse(v).to_i
      rescue
        ok &= true
      end
    end

    ok
  end

  # -----------------------
  # PAGINAÇÃO com Pagy
  # -----------------------
notas_filtradas = notas_filtradas.sort_by { |n| n["created_at"] || Time.now }.reverse
@pagy, @notas_paginadas = pagy_array(notas_filtradas, items: 10)

end




def show
  chave = params[:id].to_s
  cpf   = params[:cpf]

  # Consulta na API novamente, como antes
  resposta_api = ApiCliente.consultar_notas(cpf)

  unless resposta_api[:success]
    redirect_to notas_fiscais_path, alert: "Não foi possível consultar as notas."
    return
  end

  consulta_result = resposta_api[:body] || {}
  notas = Array(consulta_result["notas"])

  # Encontra a nota solicitada pela CHAVE
  @nota = notas.find { |n| n["CHAVE"].to_s == chave }

  unless @nota
    redirect_to notas_fiscais_path, alert: "Nota não encontrada para a chave #{chave}."
    return
  end

  # Busca o log no banco para mostrar o payload enviado
  @log = current_user.emission_logs.find_by(chave: chave)

  # Caso não exista o log, evita erro
  @payload_enviado = @log&.nota_payload
  @resposta_log    = @log&.resposta_payload

  # XML retornado pela consulta
  xml_base64 = @nota["XML"] || @nota["xml"] || @nota["xml_assinado"]

  if xml_base64.present?
    begin
      @xml_assinado = Base64.decode64(xml_base64)
    rescue => e
      @xml_assinado = "Erro ao decodificar XML: #{e.message}"
    end
  else
    @xml_assinado = nil
  end

  # A resposta exibida será a nota encontrada na API
  @resposta = @nota
end



  def new
    @nota_fiscal = NotaFiscal.new

 @cidades_ibge = {
      "Porto Velho - RO" => "1100205",
      "Ji-Paraná - RO" => "1100122",
      "Ariquemes - RO" => "1100024",
      "Candeias do Jamari - RO" => "1100800",
      "Vilhena - RO" => "1100304",
      "Guajará-Mirim - RO" => "1100106",
      "Cacoal - RO" => "1100040",
      "Jaru - RO" => "1100114",
      "Machadinho d’Oeste - RO" => "1100098",
      "Pimenta Bueno - RO" => "1100189"
    }

  end

  def edit
  end

  def create
  nota = params.require(:nota).permit!.to_h
  nota["prods"] = normalizar_produtos(nota["prods"])

  cert = CertificadoService.get_certificado(current_user)

  unless cert
    redirect_to new_notas_fiscai_path, alert: "Certificado digital não encontrado. Cadastre o PFX antes de emitir."
    return
  end

  payload = {
    pfx_base64: cert[:pfx],
    senha_certificado: cert[:senha],
    nota: nota
  }

  resposta = ApiCliente.emitir_nfe(
    pfx_base64: payload[:pfx_base64],
    senha: payload[:senha_certificado],
    nota: payload[:nota]
  )

  Rails.logger.info "RESPOSTA API: #{resposta.inspect}"

  body = resposta[:body] || resposta["body"] || {}

  # ============================
  # 1) PEGAR XML ASSINADO
  # ============================
  xml_base64 = body["xml_assinado"] || body[:xml_assinado]

  if xml_base64.blank?
    redirect_to new_notas_fiscai_path, alert: "A API não retornou o XML assinado da NF-e. (Campo xml_assinado está vazio)"
    return
  end

  # ============================
  # 2) DECODIFICAR XML
  # ============================
  begin
    require "base64"
    require "nokogiri"

    xml = Base64.decode64(xml_base64)
    doc = Nokogiri::XML(xml)

  rescue => e
    redirect_to new_notas_fiscai_path, alert: "Erro ao decodificar o XML da NF-e: #{e.message}"
    return
  end

  # ============================
  # 3) EXTRAIR A CHAVE DA NF-e
  # ============================
  begin
    # XPath funciona mesmo com namespaces
    chave = doc.xpath("//*[local-name()='infNFe']/@Id").text.gsub(/^NFe/, "")

    if chave.blank?
      redirect_to new_notas_fiscai_path, alert: "Erro: XML recebido não possui uma chave válida (infNFe/@Id)."
      return
    end

  rescue => e
    redirect_to new_notas_fiscai_path, alert: "Erro ao extrair a chave da NF-e: #{e.message}"
    return
  end

  # ============================
  # 4) SALVAR LOG
  # ============================
  log = current_user.emission_logs.create!(
    chave: chave,
    nota_payload: payload[:nota],
    resposta_payload: resposta
  )

  # ============================
  # 5) REDIRECIONAR
  # ============================
  redirect_to notas_fiscai_path(chave, cpf: current_user.cpf)
end



  def update
    if @nota_fiscal.update(nota_fiscal_params)
      redirect_to @nota_fiscal, notice: "Nota fiscal atualizada.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @nota_fiscal.destroy!
    redirect_to notas_fiscais_path, notice: "Nota fiscal removida.", status: :see_other
  end

  private

  def set_nota_fiscal
    @nota_fiscal = NotaFiscal.find(params[:id])
  end

  def nota_fiscal_params
    params.require(:nota_fiscal).permit(:usuario_id, :documento_emitente, :inscricao_estadual, :serie, :numero, :data_emissao, :status_autorizacao, :mensagem_autorizacao, :protocolo, :data_autorizacao, :cancelada, :data_cancelamento, :xml_assinado, :resposta_autorizacao)
  end

  def normalizar_produtos(prods_param)
    return [] unless prods_param

    if prods_param.is_a?(Array)
      prods_param.compact
    else
      prods_param
        .sort_by { |key, _| key.to_i }
        .map { |_, value| value }
    end
  end

  def cpf_padrao
    current_user.emission_logs.order(created_at: :desc).limit(1).map { |log| log.nota_payload.dig("emit", "CPF") }.compact.first
  end
end
