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
#

module WorkPackages::Scopes
  module ForScheduling
    extend ActiveSupport::Concern

    class_methods do
      # Fetches all work packages that need to be evaluated for eventual rescheduling after a related (i.e. follows/precedes
      # and hierarchy) work package is modified or created.
      #
      # The SQL relies on a recursive CTE which will fetch all work packages that are connected to the rescheduled work package
      # via relations (follows/precedes and/or hierarchy) either directly or transitively. It will do so by increasing the relation path
      # length one at a time and will stop on that path if the work package evaluated to be added is either:
      # * itself scheduled manually
      # * having all of it's children scheduled manually
      #
      # The children themselves are scheduled manually if all of their children are scheduled manually which repeats itself down to the leaf
      # work packages. So another way of putting it, and that is how the sql statement works, is that a work package is considered to
      # be scheduled manually if *all* of the paths to their leafs have at least one work package that is scheduled manually.
      # For example in case of the hierarchy:
      # A and B <- hierarchy (C is parent of both A and B) - C <- hierarchy - D
      # if A and B are both scheduled manually, C is also scheduled manually and so is D. But if only A is scheduled manually,
      # B, C and D are scheduled automatically.
      #
      # The recursiveness will of course also stop if no more work packages can be added.
      #
      # The work packages can either be connected via a follows relationship, a hierarchy relationship
      # or a combination of both.
      # E.g. in a graph of
      #   A  <- follows - B <- hierarchy (C is parent of B) - C <- follows D
      #
      # D would also be subject to reschedule.
      #
      # At least for hierarchical relationships, we need to follow the relationship in both directions.
      # E.g. in a graph of
      #   A  <- follows - B - hierarchy (B is parent of C) -> C <- follows D
      #
      # D would also be subject to reschedule.
      #
      # That possible switch in direction means that we cannot simply get all possibly affected work packages by one
      # SQL query which the DAG implementation would have allowed us to do otherwise.
      #
      # Currently, we do not rely on DAG for increasing the path length at all. We are still employing it in the check
      # for whether all paths to the leaf have a manually scheduled work package.
      #
      # A further improvement in performance might be reachable by also employing DAG mechanisms to increase the path length.
      #
      # @param work_packages WorkPackage[] A set of work packages for which the set of related work packages that might
      # be subject to reschedule is fetched.
      def for_scheduling(work_packages)
        return none if work_packages.empty?

        sql = <<~SQL.squish
          WITH
            RECURSIVE
            #{scheduling_paths_sql(work_packages)}

            SELECT id
            FROM to_schedule
            WHERE
              NOT to_schedule.manually
        SQL

        where("id IN (#{sql})")
          .where.not(id: work_packages)
      end

      private

      # This recursive CTE fetches all work packages that are in a direct or transitive follows and/or hierarchy
      # relationship with the provided work package.
      #
      # Hierarchy relationships are followed up as well as down (from and to) but follows relations are only followed
      # from the predecessor to the successor (from_id to to_id).
      #
      # The CTE starts from the provided work package and for that returns:
      #   * the id of the work package
      #   * the information, that the starting work package is not manually scheduled.
      # Whether the starting work package is manually scheduled or in fact automatically scheduled does make no
      # difference but we need those four columns later on.
      #
      # For each recursive step, we return all work packages that are directly related to our current set of work
      # packages by a hierarchy (up or down) or follows relationship (only successors). For each such work package
      # the statement returns:
      #   * id of the work package that is currently at the end of a path.
      #   * the flag indicating whether the added work package is automatically or manually scheduled. This also includes
      #     whether *all* of the added work package's descendants are automatically or manually scheduled.
      #
      # Paths whose ending work package is marked to be manually scheduled are not joined with any more.
      def scheduling_paths_sql(work_packages)
        values = work_packages.map { |wp| "(#{wp.id}, false)" }.join(', ')

        <<~SQL.squish
          to_schedule (id, manually) AS (
            SELECT * FROM (VALUES#{values}) AS t(id, manually)

            UNION

            SELECT
              relations.from_id id,
              scheduling.manually
            FROM
              to_schedule
            JOIN LATERAL
              (
                SELECT
                  from_id,
                  to_id
                FROM
                  relations
                WHERE NOT to_schedule.manually
                  AND (relations.to_id = to_schedule.id AND relations.relation_type = '#{Relation::TYPE_FOLLOWS}')
              UNION
                SELECT
                  CASE
                    WHEN work_package_hierarchies.ancestor_id = to_schedule.id
                    THEN work_package_hierarchies.descendant_id
                    ELSE work_package_hierarchies.ancestor_id
                    END from_id,
                  to_schedule.id to_id
                FROM
                  work_package_hierarchies
                WHERE
                  NOT to_schedule.manually
                  AND (work_package_hierarchies.ancestor_id = to_schedule.id
                       OR work_package_hierarchies.descendant_id = to_schedule.id)
              ) relations ON relations.to_id = to_schedule.id
            LEFT JOIN LATERAL (
              SELECT
                work_package_id,
                bool_and(manually) manually
              FROM
              (
                SELECT
                  origin.ancestor_id work_package_id,
                  origin.descendant_id leaf_id,
                  bool_or(leaves_wp.schedule_manually OR up_wp.schedule_manually) manually
                FROM
                  work_package_hierarchies origin
                JOIN
                  work_package_hierarchies down
                ON
                  origin.ancestor_id = down.ancestor_id
                JOIN
                  work_package_hierarchies up
                ON
                  origin.descendant_id = up.descendant_id
                  AND down.descendant_id = up.ancestor_id
                JOIN
                  work_packages leaves_wp
                ON leaves_wp.id = origin.descendant_id
                JOIN
                  work_packages up_wp
                ON up_wp.id = up.ancestor_id
                WHERE EXISTS (
                  SELECT ancestor_id
                  FROM work_package_hierarchies leaves
                  GROUP BY ancestor_id
                  HAVING MAX(generations) = 0 AND leaves.ancestor_id = origin.descendant_id
                ) AND origin.ancestor_id = relations.from_id
                GROUP BY origin.ancestor_id, origin.descendant_id
              ) scheduling
              GROUP BY work_package_id
            ) scheduling ON scheduling.work_package_id = relations.from_id
          )
        SQL
      end
    end
  end
end
