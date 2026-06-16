module Vault
  # Pure resolution for the {{pass(id)}} wiki macro. Kept separate from the macro/view
  # layer so it can be unit-tested and later re-pointed at other backends (e.g. Vaultwarden).
  module PasswordLink
    # @return [Hash] { state: :ok, key: <Vault::Key> } | { state: :no_access } | { state: :not_found }
    def self.resolve(id)
      key = Vault::Key.find_by(id: id)
      return { state: :not_found } if key.nil?
      if User.current.allowed_to?(:view_keys, key.project) &&
         key.whitelisted?(User, key.project)
        { state: :ok, key: key }
      else
        { state: :no_access }
      end
    end
  end
end
