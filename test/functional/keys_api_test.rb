require File.expand_path('../../test_helper', __FILE__)

# Rails 7.2 / Redmine 6.1 keyword-argument syntax. Covers the JSON write API
# (create/update/destroy via API key) and the tags-no-longer-500 path.
class KeysApiTest < Vault::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles
  plugin_fixtures :keys, :vault_tags, :keys_vault_tags

  def setup
    Role.find(1).add_permission!(:view_keys)
    Role.find(1).add_permission!(:edit_keys)
    Project.find(1).enabled_module_names = [:keys]
    Setting.plugin_vault['use_null_encryption'] = 'on'
    Setting.rest_api_enabled = '1'
    @token = User.find(2).api_key
  end

  def test_api_index_returns_array
    get :index, params: { project_id: 1, key: @token, format: 'json' }
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)
  end

  def test_api_show_returns_decrypted_body
    get :show, params: { project_id: 1, id: 1, key: @token, format: 'json' }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'server1', json['name']
    assert_equal '123456', json['body']
  end

  def test_api_create_with_tags_as_array
    assert_difference 'Vault::Key.count', 1 do
      post :create, params: {
        project_id: 1, key: @token, format: 'json',
        vault_key: { name: 'apidb', type: 'Vault::Password', login: 'root',
                     body: 'secret', tags: ['ssh', 'prod'] }
      }
    end
    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 'apidb', json['name']
    assert_equal 'secret', json['body']
    assert_equal ['ssh', 'prod'], json['tags']

    key = Vault::Password.find_by(name: 'apidb')
    assert key.tags.all? { |t| t.project_id == 1 }
  end

  def test_api_create_with_tags_as_string
    post :create, params: {
      project_id: 1, key: @token, format: 'json',
      vault_key: { name: 'apidb2', type: 'Vault::Password', tags: 'ssh, prod' }
    }
    assert_response :created
    assert_equal ['ssh', 'prod'], JSON.parse(response.body)['tags']
  end

  def test_api_update
    put :update, params: {
      project_id: 1, id: 1, key: @token, format: 'json',
      vault_key: { login: 'newlogin', tags: ['mysql'] }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'newlogin', json['login']
    assert_equal ['mysql'], json['tags']
  end

  def test_api_destroy
    assert_difference 'Vault::Key.count', -1 do
      delete :destroy, params: { project_id: 1, id: 1, key: @token, format: 'json' }
    end
    assert_response :no_content
  end

  def test_api_create_requires_permission
    Role.find(1).remove_permission!(:edit_keys)
    post :create, params: {
      project_id: 1, key: @token, format: 'json',
      vault_key: { name: 'denied', type: 'Vault::Password' }
    }
    assert_response :forbidden
    refute Vault::Key.exists?(name: 'denied')
  end
end
