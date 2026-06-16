# Vault constants
module Vault
  KEYFILES_DIR = "#{Rails.root}/keys".freeze
end
Dir.mkdir(Vault::KEYFILES_DIR) unless Dir.exist?(Vault::KEYFILES_DIR)

# Load cipher modules (order matters)
require File.expand_path('vendor/null_cipher', __dir__)
require File.expand_path('vendor/vault_cipher', __dir__)
require File.expand_path('vendor/redmine_cipher', __dir__)
require File.expand_path('vendor/encryptor', __dir__)
require File.expand_path('vendor/file_cipher', __dir__)
require File.expand_path('vendor/body_cipher', __dir__)

# Project association
require File.expand_path('vendor/project_patch', __dir__)
require File.expand_path('lib/vault/password_link', __dir__)

# Hook for stylesheet
class VaultViewHook < Redmine::Hook::ViewListener
  def view_layouts_base_html_head(context = {})
    i18n = {
      insert_pass:   l('key.toolbar.insert_pass'),
      picker_title:  l('key.picker.title'),
      picker_search: l('key.picker.search'),
      picker_empty:  l('key.picker.empty')
    }
    stylesheet_link_tag('font-awesome.css', plugin: 'vault') +
      stylesheet_link_tag('vault', plugin: 'vault') +
      javascript_include_tag('vault', plugin: 'vault') +
      javascript_tag("window.VAULT_I18N = #{i18n.to_json};")
  end
end

Redmine::Plugin.register :vault do
  name 'Vault plugin (fork)'
  author 'noshutdown.ru'
  description 'Plugin for keep keys and passwords. Fork of noshutdown.ru/redmine-plugins-vault'
  version '0.8.0'
  url 'https://git.half.net.ua/polumish/redmine-vault'
  author_url 'https://noshutdown.ru/'

  project_module :keys do
    permission :export_keys, keys: [ :keys_to_pdf ]
    permission :download_keys, key_files: [ :download, :preview ], key_attachments: [ :download, :preview ]
    permission :view_keys, keys: [ :index, :edit, :show, :context_menu, :picker, :card ]
    permission :edit_keys, keys: [ :index, :new, :create, :edit, :show, :update, :destroy, :copy ]
    permission :manage_whitelist_keys, keys: [ :index, :create, :edit, :show, :update, :copy ]
    permission :whitelist_keys, keys: [ :index, :edit, :show, :context_menu ]
  end

  menu :project_menu, :keys, { controller: 'keys', action: 'index' }, caption: Proc.new {I18n.t('label_module')}, after: :activity, param: :project_id
  settings default: { 'empty' => true }, partial: 'settings/vault_settings'
  menu :admin_menu, :vault, { controller: 'vault_settings', action: 'index' }, caption: :label_vault, html: { class: 'icon' }
end

# Wiki macro {{pass(id)}} — registered here (NOT in lib/vault/, which Zeitwerk
# autoloads and would require a matching Vault::Macros constant). References
# Vault::PasswordLink (loaded above) only at macro-call time.
Redmine::WikiFormatting::Macros.register do
  desc "Link to a Vault password.\n\n{{pass(42)}}\n{{pass(42, \"custom label\")}}"
  macro :pass do |obj, args|
    id = args[0].to_s.strip
    label = args[1].to_s.strip.gsub(/\A["']|["']\z/, '').presence
    res = Vault::PasswordLink.resolve(id)
    lock = content_tag(:i, ''.html_safe, class: 'fa fa-lock fa-fw')
    case res[:state]
    when :ok
      key = res[:key]
      lock + link_to(label || key.name,
                     url_for(controller: 'keys', action: 'show',
                             project_id: key.project, id: key.id, only_path: true),
                     class: 'vault-pass-link')
    when :no_access
      content_tag(:span, lock + ' '.html_safe + l('key.macro.no_access'), class: 'vault-pass-noaccess')
    else
      content_tag(:span, lock + ' '.html_safe + l('key.macro.not_found'), class: 'vault-pass-notfound')
    end
  end
end
