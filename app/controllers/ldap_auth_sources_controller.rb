#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2022 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

class LdapAuthSourcesController < AuthSourcesController
  include PaginationHelper
  layout 'admin'
  menu_item :ldap_authentication

  before_action :require_admin
  before_action :block_if_password_login_disabled

  def index
    @auth_sources = LdapAuthSource.page(page_param)
                              .per_page(per_page_param)
  end

  def new
    @auth_source = LdapAuthSource.new
  end

  def create
    @auth_source = LdapAuthSource.new permitted_params.auth_source
    if @auth_source.save
      flash[:notice] = I18n.t(:notice_successful_create)
      redirect_to action: :index
    else
      render action: :new
    end
  end

  def edit
    @auth_source = LdapAuthSource.find(params[:id])
  end

  def update
    @auth_source = LdapAuthSource.find(params[:id])
    updated = permitted_params.auth_source
    updated.delete :account_password if updated[:account_password].blank?

    if @auth_source.update updated
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to action: 'index'
    else
      render action: :edit
    end
  end

  def test_connection
    @auth_method = LdapAuthSource.find(params[:id])
    begin
      @auth_method.test_connection
      flash[:notice] = I18n.t(:notice_successful_connection)
    rescue StandardError => e
      flash[:error] = I18n.t(:error_unable_to_connect, value: e.message)
    end
    redirect_to action: 'index'
  end

  def destroy
    @auth_source = LdapAuthSource.find(params[:id])
    if @auth_source.users.empty?
      @auth_source.destroy

      flash[:notice] = t(:notice_successful_delete)
    else
      flash[:warning] = t(:notice_wont_delete_auth_source)
    end
    redirect_to action: 'index'
  end

  protected

  def default_breadcrumb
    if action_name == 'index'
      t(:label_auth_source_plural)
    else
      ActionController::Base.helpers.link_to(t(:label_auth_source_plural), ldap_auth_sources_path)
    end
  end

  def show_local_breadcrumb
    true
  end

  def block_if_password_login_disabled
    render_404 if OpenProject::Configuration.disable_password_login?
  end
end
