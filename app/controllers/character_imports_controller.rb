class CharacterImportsController < ApplicationController
  before_action :require_account, only: %i[new create]

  def new
    @errors = []
  end

  def create
    result = CharacterImportService.call(upload: params[:file], account: current_account)
    if result.success?
      redirect_to character_path(result.character), notice: "Character imported as a draft. Review it before finalizing."
    else
      @errors = result.errors
      render :new, status: :unprocessable_entity
    end
  end

  def template
    kind = params[:kind].to_s.downcase
    content_type = kind == "json" ? "application/json" : "text/csv"
    send_data CharacterImportService.template_for(kind),
      filename: "nimble-character-import-template.#{kind}",
      type: content_type,
      disposition: "attachment"
  rescue ArgumentError => error
    redirect_to new_character_import_path, alert: error.message
  end
end
