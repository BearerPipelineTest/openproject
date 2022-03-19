class AddParentIdToWp < ActiveRecord::Migration[6.1]
  # This migration handles two cases:
  #   * migrating from OP pre 7.4 (which includes setting up a new instance)
  #   * migrating from OP between 7.4 and 12.0
  #
  # For the former, the usage of typed_dag is ignored throughout the migrations and as such,
  # the tables will have the following layout:
  # work_packages:
  #   parent_id - integer
  #   root_id - integer
  #   lft - integer
  #   rgt - integer
  #   ...(other non relevant columns)
  #
  # relations:
  #   from_id - integer
  #   to_id - integer
  #   relation_type - varchar
  #   delay - varchar
  #   description - varchar
  #
  # In case migrating from OP between 7.4 and 12.0 typed_dag was in place and the tables
  # will have the following layout:
  # work_packages:
  #   ...(other non relevant columns)
  #
  # relations:
  #   from_id - integer
  #   to_id - integer
  #   hierarchy - integer
  #   relates - integer
  #   follows - integer
  #   blocks - integer
  #   includes - integer
  #   requires - integer
  #   duplicates - integer
  #   count - integer
  #   delay - varchar
  #   description - varchar
  def up
    if column_exists? :work_packages, :parent_id
      up_from_pre_typed_dag
    else
      up_from_typed_dag
    end

    add_relation_index

    add_closure_tree_table

    WorkPackage.rebuild!
  end

  def down
    # TODO
  end

  private

  def up_from_pre_typed_dag
    remove_nested_set_columns
  end

  def up_from_typed_dag
    add_column :work_packages, :parent_id, :integer

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE
            work_packages
          SET
            parent_id = from_id
          FROM relations
          WHERE
            hierarchy = 1
            AND relates = 0
            AND duplicates = 0
            AND blocks = 0
            AND follows = 0
            AND includes = 0
            AND requires = 0
            AND work_packages.id = relations.to_id
        SQL
      end
    end

    remove_column :relations, :hierarchy, type: :integer

    reversible do |dir|
      dir.down do
        execute <<~SQL.squish
          DELETE FROM relations
          WHERE hierarchy > 0
        SQL
        # supports relying on fast "Index Only Scan" for finding work packages that need to be rescheduled after a work package
        # has been moved
        add_index :relations,
                  %i(to_id hierarchy follows from_id),
                  name: 'index_relations_hierarchy_follows_scheduling',
                  where: <<~SQL.squish
                    relations.relates = 0
                    AND relations.duplicates = 0
                    AND relations.blocks = 0
                    AND relations.includes = 0
                    AND relations.requires = 0
                    AND (hierarchy + relates + duplicates + follows + blocks + includes + requires > 0)
                  SQL

        add_index :relations,
                  %i(from_id to_id hierarchy),
                  name: 'index_relations_only_hierarchy',
                  where: <<~SQL.squish
                    relations.relates = 0
                    AND relations.duplicates = 0
                    AND relations.follows = 0
                    AND relations.blocks = 0
                    AND relations.includes = 0
                    AND relations.requires = 0
                  SQL
      end
    end
  end

  def add_closure_tree_table
    # Copied from closure tree migration
    # rubocop:disable Rails/CreateTableWithTimestamps
    create_table :work_package_hierarchies, id: false do |t|
      t.integer :ancestor_id, null: false
      t.integer :descendant_id, null: false
      t.integer :generations, null: false
    end

    add_index :work_package_hierarchies, %i[ancestor_id descendant_id generations],
              unique: true,
              name: "work_package_anc_desc_idx"

    add_index :work_package_hierarchies, [:descendant_id],
              name: "work_package_desc_idx"
    # End copied from closure tree migration
    # rubocop:enable Rails/CreateTableWithTimestamps
  end

  def add_relation_index
    add_index :relations, %i[from_id to_id relation_type],
              unique: true
  end

  def remove_nested_set_columns
    remove_column :work_packages, :root_id
    remove_column :work_packages, :lft
    remove_column :work_packages, :rgt
  end
end
