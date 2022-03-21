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

class Relation < ApplicationRecord
  belongs_to :from, class_name: 'WorkPackage'
  belongs_to :to, class_name: 'WorkPackage'


  TYPE_RELATES      = 'relates'.freeze
  TYPE_DUPLICATES   = 'duplicates'.freeze
  TYPE_DUPLICATED   = 'duplicated'.freeze
  TYPE_BLOCKS       = 'blocks'.freeze
  TYPE_BLOCKED      = 'blocked'.freeze
  TYPE_PRECEDES     = 'precedes'.freeze
  TYPE_FOLLOWS      = 'follows'.freeze
  TYPE_INCLUDES     = 'includes'.freeze
  TYPE_PARTOF       = 'partof'.freeze
  TYPE_REQUIRES     = 'requires'.freeze
  TYPE_REQUIRED     = 'required'.freeze
  TYPE_HIERARCHY    = 'hierarchy'.freeze

  TYPES = {
    TYPE_RELATES => {
      name: :label_relates_to, sym_name: :label_relates_to, order: 1, sym: TYPE_RELATES
    },
    TYPE_DUPLICATES => {
      name: :label_duplicates, sym_name: :label_duplicated_by, order: 2, sym: TYPE_DUPLICATED
    },
    TYPE_DUPLICATED => {
      name: :label_duplicated_by, sym_name: :label_duplicates, order: 3,
      sym: TYPE_DUPLICATES, reverse: TYPE_DUPLICATES
    },
    TYPE_BLOCKS => {
      name: :label_blocks, sym_name: :label_blocked_by, order: 4, sym: TYPE_BLOCKED
    },
    TYPE_BLOCKED => {
      name: :label_blocked_by, sym_name: :label_blocks, order: 5,
      sym: TYPE_BLOCKS, reverse: TYPE_BLOCKS
    },
    TYPE_PRECEDES => {
      name: :label_precedes, sym_name: :label_follows, order: 6,
      sym: TYPE_FOLLOWS, reverse: TYPE_FOLLOWS
    },
    TYPE_FOLLOWS => {
      name: :label_follows, sym_name: :label_precedes, order: 7,
      sym: TYPE_PRECEDES
    },
    TYPE_INCLUDES => {
      name: :label_includes, sym_name: :label_part_of, order: 8,
      sym: TYPE_PARTOF
    },
    TYPE_PARTOF => {
      name: :label_part_of, sym_name: :label_includes, order: 9,
      sym: TYPE_INCLUDES, reverse: TYPE_INCLUDES
    },
    TYPE_REQUIRES => {
      name: :label_requires, sym_name: :label_required, order: 10,
      sym: TYPE_REQUIRED
    },
    TYPE_REQUIRED => {
      name: :label_required, sym_name: :label_requires, order: 11,
      sym: TYPE_REQUIRES, reverse: TYPE_REQUIRES
    }
  }.freeze

  include ::Scopes::Scoped

  scopes :follows_non_manual_ancestors,
         :types,
         :visible

  scope :of_work_package,
        ->(work_package) { where(from: work_package).or(where(to: work_package)) }

  validates_numericality_of :delay, allow_nil: true

  validates :to, uniqueness: { scope: :from }

  before_validation :reverse_if_needed

  def self.relation_column(type)
    if TYPES.key?(type) && TYPES[type][:reverse]
      TYPES[type][:reverse]
    elsif TYPES.key?(type) || type == TYPE_HIERARCHY
      type
    end
  end

  def self.from_parent_to_self_and_descendants(work_package)
    # TODO: handle transitive connections
    where(from_id: work_package.self_and_ancestors.select(:id))
      .where(to_id: work_package.self_and_descendants.select(:id))
  end

  def self.from_self_and_descendants_to_ancestors(work_package)
    # using parent.self_and_ancestors to be able to cope with unpersisted parent
    # TODO: handle transitive connections
    where(from_id: work_package.self_and_descendants.select(:id))
      .where(to_id: work_package.parent.self_and_ancestors.select(:id))
  end

  def self.hierarchy_or_follows
    with_type_columns_0(_dag_options.type_columns - %i(hierarchy follows))
      .non_reflexive
  end

  def self.hierarchy_or_reflexive
    with_type_columns_0(_dag_options.type_columns - %i(hierarchy))
  end

  def self.non_hierarchy_of_work_package(work_package)
    of_work_package(work_package)
      .non_hierarchy
      .direct
  end

  def other_work_package(work_package)
    from_id == work_package.id ? to : from
  end

  # Returns the relation type for +work_package+
  def relation_type_for(work_package)
    if TYPES[relation_type]
      if from_id == work_package.id
        relation_type
      else
        TYPES[relation_type][:sym]
      end
    end
  end

  def reverse_type
    Relation::TYPES[relation_type] && Relation::TYPES[relation_type][:sym]
  end

  def label_for(work_package)
    key = from_id == work_package.id ? :name : :sym_name

    TYPES[relation_type] ? TYPES[relation_type][key] : :unknown
  end

  def successor_soonest_start
    if relation_type == TYPE_FOLLOWS && (to.start_date || to.due_date)
      (to.due_date || to.start_date) + 1 + (delay || 0)
    end
  end

  def <=>(other)
    TYPES[relation_type][:order] <=> TYPES[other.relation_type][:order]
  end

  # delay is an attribute of Relation but its getter is masked by delayed_job's #delay method
  # here we overwrite dj's delay method with the one reading the attribute
  # since we don't plan to use dj with Relation objects, this should be fine
  def delay
    self[:delay]
  end

  TYPES.keys.each do |type|
    define_method "#{type}?" do
      canonical_type == self.class.canonical_type(type)
    end
  end

  def canonical_type
    self.class.canonical_type(relation_type)
  end

  def self.canonical_type(relation_type)
    if TYPES.key?(relation_type) &&
       TYPES[relation_type][:reverse]
      TYPES[relation_type][:reverse]
    else
      relation_type
    end
  end

  private

  def shared_hierarchy?
    to.ancestors.where(id: from.id)
      .or(from.ancestors.where(id: to.id))
      .any?
  end

  def validate_sanity_of_relation
    return unless from && to

    errors.add :to_id, :invalid if from_id == to_id
    errors.add :to_id, :not_same_project unless from.project_id == to.project_id ||
                                                Setting.cross_project_work_package_relations?
    errors.add :base, :cant_link_a_work_package_with_a_descendant if shared_hierarchy?
  end

  # Reverses the relation if needed so that it gets stored in the proper way
  def reverse_if_needed
    if TYPES.key?(relation_type) && TYPES[relation_type][:reverse]
      work_package_tmp = to
      self.to = from
      self.from = work_package_tmp
      self.relation_type = TYPES[relation_type][:reverse]
    end
  end
end
