class Admin::GameModulesController < Admin::BaseController
  before_action :set_game_module, only: %i[destroy reimport]

  def new
    @game_module = GameModule.new
  end

  def create
    @game_module = GameModule.new(package: params.dig(:game_module, :package))
    if @game_module.save
      ModuleImportJob.perform_later(@game_module)
      redirect_to game_module_path(@game_module), notice: "Módulo subido; importando en segundo plano."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    FileUtils.rm_rf(@game_module.extracted_dir)
    @game_module.destroy!
    redirect_to root_path, notice: "Módulo eliminado."
  end

  def reimport
    @game_module.update!(status: "pending", error_message: nil)
    ModuleImportJob.perform_later(@game_module)
    redirect_to game_module_path(@game_module), notice: "Reimportando módulo."
  end

  private

  def set_game_module
    @game_module = GameModule.find_by!(slug: params[:slug])
  end
end
