class LoginController < ApplicationController
  require 'uri'

  def login
    cookies.delete :query_string
    cookies.signed[:query_string] = request.query_string
    referer = request.env["HTTP_REFERER"]
    cookies.signed[:referer] = referer
    logger.info "the query_string is #{cookies.signed[:query_string]}"
    logger.info "the referer is #{cookies.signed[:referer]}"
    redirect_to signin_path :cas
  end

  def create
    uri = URI.parse(cookies.signed[:referer])
    username = request.env["omniauth.auth"][:uid]
    email = request.env["omniauth.auth"][:extra][configatron.cas.email_attribute]
    if request.env["omniauth.auth"][:extra][configatron.cas.name_attribute]
      name = request.env["omniauth.auth"][:extra][configatron.cas.name_attribute].split(',').reverse.each { |x| x.strip }.join(' ')
    else
      name = username
    end

    sso = SingleSignOn.parse(cookies.signed[:query_string], configatron.sso.secret)
    sso.email = email
    sso.name = name
    sso.username = username
    sso.external_id = username # unique to your application
    sso.sso_secret = configatron.sso.secret



    #if there are groups in the data returned by CAS see if we need
    #filter through the allow and deny groups
    allowed_groups = true
    denied_groups = false

    if configatron.filter_by_groups
      #if there are groups in the data returned by CAS see if we need
      #filter through the allow and deny groups
      allowed_groups = true
      denied_groups = false
      if request.env["omniauth.auth"][:extra][configatron.sso.groups.name]
        users_groups = request.env["omniauth.auth"][:extra]['Groups'].split(', ')
        allowed_groups = allowed_group(users_groups) if configatron.sso.groups.allow
        denied_groups = denied_group(users_groups) if configatron.sso.groups.deny
      end
    end
    if allowed_groups && !denied_groups
      redirect_to sso.to_url("#{uri.scheme}://#{uri.host}#{configatron.sso.login.path}")
    else
      redirect_to failure
    end
  end


  def failure
  end

  protected


  def allowed_group(users_groups)
    allowed_set = Set.new(configatron.sso.groups.allow_list.split('|'))
    users_set = Set.new(users_groups)
    #is there and intersection in the groups
    (allowed_set & users_set).empty?
  end

  def denied_group(users_groups)
    denied_set = Set.new(configatron.sso.groups.deny_list.split('|'))
    users_set = Set.new(users_groups)
    #is there and intersection in the groups
    !(denied_set & users_set).empty?
  end

  def after_create_account(user, auth)
    user.update_attribute(:approved, SiteSetting.cas_sso_user_approved)
    ::PluginStore.set("cas", "cas_uid_#{auth[:username]}", {user_id: user.id})
  end


  def auth_hash
    request.env['omniauth.auth']
  end

end
