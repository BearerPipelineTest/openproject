#  OpenProject is an open source project management software.
#  Copyright (C) 2010-2022 the OpenProject GmbH
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License version 3.
#
#  OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
#  Copyright (C) 2006-2013 Jean-Philippe Lang
#  Copyright (C) 2010-2013 the ChiliProject Team
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#  See COPYRIGHT and LICENSE files for more details.

module WorkPackages::Scopes
  module Relatable
    extend ActiveSupport::Concern

    class_methods do
      def relatable(work_package, relation_type)
        return all if work_package.new_record?

        not_having_directed_relation(work_package, relation_type)
          .not_having_direct_relation(work_package)
          .where.not(id: work_package)
      end

      def not_having_direct_relation(work_package)
        where.not(id: Relation.where(from: work_package).select(:to_id))
             .where.not(id: Relation.where(to: work_package).select(:from_id))
      end

      def not_having_directed_relation(work_package, relation_type)
        sql = <<~SQL.squish
          WITH
            RECURSIVE
            #{non_relatable_paths_sql(work_package, relation_type)}

            SELECT id
            FROM #{RELATED_CTE_NAME}
        SQL

        where("work_packages.id NOT IN (#{sql})")
      end

      private

      RELATED_CTE_NAME = 'related'.freeze

      def non_relatable_paths_sql(work_package, relation_type)
        <<~SQL.squish
          #{RELATED_CTE_NAME} (id, from_hierarchy) AS (

              SELECT * FROM (VALUES(#{work_package.id}, false)) AS t(id, from_hierarchy)

            UNION

              SELECT
                relations.id,
                relations.from_hierarchy
              FROM
                #{RELATED_CTE_NAME}
              JOIN LATERAL (
                #{joined_existing_connections(relation_type)}
              ) relations ON 1 = 1
          )
        SQL
      end

      def joined_existing_connections(relation_type)
        unions = [existing_hierarchy_lateral]

        if relation_type != Relation::TYPE_RELATES
          unions << existing_relation_of_type_lateral(relation_type)
        end

        unions.join(' UNION ')
      end

      def existing_relation_of_type_lateral(relation_type)
        canonical_type = Relation.canonical_type(relation_type)

        direction1, direction2 = if canonical_type == relation_type
                                   %w[from_id to_id]
                                 else
                                   %w[to_id from_id]
                                 end

        <<~SQL.squish
          SELECT
            #{direction1} id,
            false from_hierarchy
          FROM
            relations
          WHERE (relations.#{direction2} = #{RELATED_CTE_NAME}.id AND relations.relation_type = '#{canonical_type}')
        SQL
      end

      def existing_hierarchy_lateral
        <<~SQL.squish
          SELECT
            CASE
              WHEN work_package_hierarchies.ancestor_id = related.id
              THEN work_package_hierarchies.descendant_id
              ELSE work_package_hierarchies.ancestor_id
              END id,
            true from_hierarchy
          FROM
            work_package_hierarchies
          WHERE
            #{RELATED_CTE_NAME}.from_hierarchy = false AND
            (work_package_hierarchies.ancestor_id = #{RELATED_CTE_NAME}.id OR work_package_hierarchies.descendant_id = #{RELATED_CTE_NAME}.id)
        SQL
      end
    end
  end
end
