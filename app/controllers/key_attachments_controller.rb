class KeyAttachmentsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  accept_api_auth :download, :preview

  def download
    att = find_attachment
    return if att.nil?
    data = att.decrypt_data
    return render_404 if data.nil?
    send_data data, filename: filename(att), disposition: 'attachment'
  end

  def preview
    att = find_attachment
    return if att.nil?
    data = att.decrypt_data
    return render_404 if data.nil?
    mime = Marcel::MimeType.for(StringIO.new(data), name: filename(att))
    send_data data, filename: filename(att), type: mime, disposition: 'inline'
  end

  private

  # The attachment, scoped to this project's keys (no cross-project access).
  def find_attachment
    att = Vault::Attachment.find_by(id: params[:id])
    if att.nil? || att.key&.project_id != @project.id
      redirect_to project_keys_path(@project), alert: t('alert.key.not_found')
      return nil
    end
    att
  end

  def filename(att)
    (att.filename.presence || "attachment-#{att.id}").to_s
  end
end
