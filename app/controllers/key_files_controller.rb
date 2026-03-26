class KeyFilesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def download
    find_key
    unless @key.nil?
      send_file "#{Vault::KEYFILES_DIR}/#{@key.file}", filename: @key.name
    end
  end

  def preview
    find_key
    unless @key.nil?
      filepath = "#{Vault::KEYFILES_DIR}/#{@key.file}"
      if File.exist?(filepath)
        mime = Marcel::MimeType.for(Pathname.new(filepath))
        send_file filepath, filename: @key.name, type: mime, disposition: "inline"
      else
        render_404
      end
    end
  end

  private

  def find_key
    @key = Vault::Key.find(params[:id])
    unless @key.project_id == @project.id
      redirect_to project_keys_path(@project), alert: t("alert.key.not_found")
      @key = nil
    end
  end
end
