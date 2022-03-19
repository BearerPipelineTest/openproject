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

module WorkPackage::Parent
  def self.prepended(base)
    base.scope :with_children, ->(*args) do
      opts = Hash(args.first)
      # noinspection RubySimplifyBooleanInspection
      neg = opts[:present] == false ? "NOT" : ""
      rel = Relation.table_name
      wp = WorkPackage.table_name

      query = "#{neg} EXISTS (SELECT 1 FROM #{rel} WHERE #{rel}.from_id = #{wp}.id AND #{rel}.hierarchy > 0"

      if opts[:in].respond_to? :arel
        subset = opts[:in].arel #                            .select() (or project()) will only add columns
        subset.projections = [WorkPackage.arel_table[:id]] # but we only need the ID, so we reset the projections

        query += " AND relations.to_id IN (#{subset.to_sql})"
      end

      query += " LIMIT 1)"

      where(query)
    end

    base.scope :without_children, ->(*args) do
      with_children Hash(args.first).merge(present: false)
    end
  end

  attr_accessor :parent_object,
                :do_halt

  def has_parent?
    !parent_id.nil?
  end
end
