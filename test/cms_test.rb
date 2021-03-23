ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CmsTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
    user_list = YAML.load_file(user_credentials)

    if user_list.key?("testperson")
      path = File.expand_path("../users.yml", __FILE__)
      user_list.delete("testperson")
      File.write(path, user_list.to_yaml)
    end
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_home
    create_document "about.md"
    create_document "changes.txt"
    create_document "history.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "history.txt"
    assert_includes last_response.body, "Edit"
    assert_includes last_response.body, "New Document"
    assert_includes last_response.body, %q(<button type="submit">Delete)
    assert_includes last_response.body, %q(<button type="button">Sign in)
  end

  def test_textfile
    create_document "history.txt", "1993 - Yukihiro Matsumoto"

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "1993 - Yukihiro Matsumoto"
  end

  def test_file_path_error
    get "/incorrect_file"
    assert_equal 302, last_response.status
    assert_equal "incorrect_file does not exist.", session[:message]
  end

  def test_markdown_doc_view
    create_document "about.md", "# Ruby is..."

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_edit_page
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_edit_page_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You need to sign in to do that.", session[:message]
  end

  def test_save_changes_success
    create_document "history.txt"

    post "history.txt/edit", {content: "new content"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "history.txt has been updated.", session[:message]

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_save_changes_success_signed_out
    create_document "history.txt"
    post "history.txt/edit", {content: "new content"}

    assert_equal 302, last_response.status
    assert_equal "You need to sign in to do that.", session[:message]
  end

  def test_new_doc_page
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")    
  end

  def test_new_doc_page_signed_out
    get "/new", {}

    assert_equal 302, last_response.status
    assert_equal "You need to sign in to do that.", session[:message]   
  end

  def test_create_file
    post "/new", {new_file: "info.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "info.txt was created.", session[:message]

    get "/"
    assert_includes last_response.body, "info.txt"
  end

  def test_create_file_signed_out
    post "/new", {new_file: "info.txt"}
    assert_equal 302, last_response.status
    assert_equal "You need to sign in to do that.", session[:message]
  end

  def test_new_file_error
    post "/new", {new_file: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_delete_file
    create_document "history.txt"

    post "/history.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "history.txt was deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/history.txt")
  end

  def test_delete_file_signed_out
    create_document "history.txt"
    post "/history.txt/delete", {}

    assert_equal 302, last_response.status
    assert_equal "You need to sign in to do that.", session[:message]
  end

  def test_sign_in_page
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"
    assert_includes last_response.body, %q(<button type="submit">Sign in)
  end

  def test_successful_sign_in
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, %q(<button type="submit">Sign out)
  end

  def test_unsuccessful_sign_in
    post "/users/signin", username: "not_admin", password: "incorrect"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_sign_out
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal 302, last_response.status
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign in"
  end

  def test_signup_page
    get "/users/signup"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"
    assert_includes last_response.body, %q(<button type="submit">Sign up)
  end

  def test_successful_signup
    post "/users/signup", username: "testperson", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Successfully signed up.", session[:message]
  end

  def test_signup_error_name_exists
    post "/users/signup", username: "admin", password: "secret"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Username already exists. Choose another."
  end

  def test_signup_error_no_username
    post "/users/signup", username: "", password: "secret"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please enter a username."
  end

  def test_signup_error_no_password
    post "/users/signup", username: "test", password: ""
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please enter a password."
  end

  def test_duplicate_file
    create_document "history.txt"

    post "/history.txt/edit", {content: "new content"}, admin_session

    post "/history.txt/copy", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "history.txt was duplicated.", session[:message]

    get "/"
    assert_includes last_response.body, "history(1).txt"
  end

  def test_duplicate_file_2
    create_document "history.txt"
    create_document "history(1).txt"

    post "/history.txt/edit", {content: "new content"}, admin_session

    post "/history.txt/copy", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "history.txt was duplicated.", session[:message]

    get "/"
    assert_includes last_response.body, "history(2).txt"
  end
end
































