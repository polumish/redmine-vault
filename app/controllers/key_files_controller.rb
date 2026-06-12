class KeyFilesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  accept_api_auth :download, :preview

  def download
    find_key
    return if @key.nil?
    data = file_data
    return render_404 if data.nil?
    send_data data, filename: download_filename, disposition: 'attachment'
  end

  def preview
    find_key
    return if @key.nil?
    data = file_data
    return render_404 if data.nil?
    mime = Marcel::MimeType.for(StringIO.new(data), name: download_filename)
    send_data data, filename: download_filename, type: mime, disposition: 'inline'
  end

  private

  def find_key
    @key = Vault::Key.find(params[:id])
    unless @key.project_id == @project.id
      redirect_to project_keys_path(@project), alert: t("alert.key.not_found")
      @key = nil
    end
  end

  # Decrypted file bytes, or nil if this key has no attached file.
  def file_data
    return nil unless @key.is_a?(Vault::KeyFile)
    @key.decrypt_file
  end

  def download_filename
    (@key.file.presence || @key.name).to_s
  end
end
