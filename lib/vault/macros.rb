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
