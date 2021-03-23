require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, "secret"
end

def signed_in?
  !session[:username].nil?
end

def require_signed_in_user
  return if signed_in?

  session[:message] = "You need to sign in to do that."
  redirect "/"
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text.to_s)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when '.txt'
    headers["Content-Type"] = 'text/plain'
    content
  when ".md"
    render_markdown(content)
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def user_credentials
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def supported_file?(file)
  supported_types = [".txt", ".md"]
  supported_types.include?(File.extname(file))
end

def unique_name?(file)
  pattern = File.join(data_path, "*")
  files = Dir.glob(pattern).map { |path| File.basename(path) }
  !files.include?(file)
end

def user_exists?(user)
  user_list = YAML.load_file(user_credentials)
  user_list.keys.include?(user)
end

def create_duplicate(file)
  file_path = File.join(data_path, file)
  content = File.read(file_path)
  ext = File.extname(file)
  new_filename = incremented_file_num(file) + ext

  new_file_path = File.join(data_path, new_filename)
  File.write(new_file_path, content)
end

def duplicate?(file)
  file.match?(/[(]\d+[)]\z/)
end

# gets the number that should be added onto the file that is going to be copied
def get_dup_number(file)
  if duplicate?(file)
    num_with_paren = file.match(/[(]\d+[)]\z/)[0]
    num_with_paren.gsub(/[()]/, "").to_i + 1
  else
    1
  end
end

# gets path of a file after its number has been incremented
def incremented_path(file, number, ext)
  incremented_file = file + "(" + number.to_s + ")"
  File.join(data_path, File.basename(incremented_file + ext))
end

# gets next available incremented file copy => example(1).txt from example.txt
def incremented_file_num(file)
  ext = File.extname(file)
  name_no_ext = File.basename(file, ".*")
  number = get_dup_number(name_no_ext)
  file_no_paren = name_no_ext.split(/[(]\d+[)]\z/)[0]

  new_file_path = incremented_path(file_no_paren, number, ext)

  while File.exist?(new_file_path)
    number += 1
    new_file_path = incremented_path(file_no_paren, number, ext)
  end

  file_no_paren + "(" + number.to_s + ")"
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end

  erb :home
end

get "/new" do
  require_signed_in_user
  erb :new_file
end

post "/new" do
  require_signed_in_user
  filename = params[:new_file].to_s
  if filename.length.zero?
    session[:message] = "A name is required."
    status 422
    erb :new_file
  elsif File.extname(filename) == ""
    session[:message] = "File extension required."
    status 422
    erb :new_file
  elsif !supported_file?(filename)
    session[:message] = "Only .txt and .md are supported."
    status 422
    erb :new_file
  elsif !unique_name?(filename)
    session[:message] = "Name must be unique."
    status 422
    erb :new_file
  else
    file_path = File.join(data_path, filename)
    File.write(file_path, "")
    session[:message] = "#{filename} was created."
    redirect "/"
  end
end

get "/:filename" do
  file_path = File.join(data_path, File.basename(params[:filename]))

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{File.basename(file_path)} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  @file = File.read(file_path)
  erb :edit_file
end

post "/:filename/edit" do
  require_signed_in_user
  filename = params[:filename]
  content = params[:content]
  file_path = File.join(data_path, filename)
  File.write(file_path, content)

  session[:message] = "#{filename} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  require_signed_in_user
  filename = params[:filename]
  file_path = File.join(data_path, filename)
  File.delete(file_path)

  session[:message] = "#{filename} was deleted."
  redirect "/"
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]
  password = params[:password]
  user_list = YAML.load_file(user_credentials)

  bcrypt_pass = nil
  if user_list.key?(username)
    bcrypt_pass = BCrypt::Password.new(user_list[username])
  end

  if bcrypt_pass == password
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  if user_exists?(params[:username])
    session[:message] = "Username already exists. Choose another."
    status 422
    erb :signup
  elsif params[:username].strip.size.zero?
    session[:message] = "Please enter a username."
    status 422
    erb :signup
  elsif params[:password].strip.size.zero?
    session[:message] = "Please enter a password."
    status 422
    erb :signup
  else
    hashed_password = BCrypt::Password.create(params[:password]).to_s
    user_list = YAML.load_file(user_credentials)
    user_list[params[:username]] = hashed_password
    File.write(user_credentials, user_list.to_yaml)

    session[:message] = "Successfully signed up."
    redirect "/"
  end
end

post "/:filename/copy" do
  require_signed_in_user
  filename = params[:filename]
  create_duplicate(filename)

  session[:message] = "#{filename} was duplicated."
  redirect "/"
end
