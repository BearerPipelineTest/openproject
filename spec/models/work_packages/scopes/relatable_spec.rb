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

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers
describe WorkPackages::Scopes::Relatable, '.relatable scope' do
  let(:project) { create(:project) }
  let(:origin) { create(:work_package, project: project) }
  let(:unrelated_work_package) { create(:work_package, project: project) }

  let(:directly_related_work_package) do
    create(:work_package, project: project).tap do |related_wp|
      create(:relation,
             relation_type: directly_related_work_package_type,
             from: origin,
             to: related_wp)
    end
  end
  let(:directly_related_work_package_type) { relation_type }
  let(:transitively_related_work_package) do
    create(:work_package, project: project).tap do |related_wp|
      create(:relation,
             relation_type: transitively_related_work_package_type,
             from: directly_related_work_package,
             to: related_wp)
    end
  end
  let(:transitively_related_work_package_type) { relation_type }

  let(:parent) do
    create(:work_package, project: project).tap do |p|
      origin.update(parent: p)
    end
  end
  let(:sibling) do
    create(:work_package, project: project, parent: parent)
  end
  #let(:predecessor) do
  #  create(:work_package, project: project).tap do |pre|
  #    create(:follows_relation, from: origin, to: pre)
  #  end
  #end
  #let(:parent) do
  #  create(:work_package, project: project).tap do |par|
  #    origin.update(parent: par)
  #  end
  #end
  #let(:grandparent) do
  #  create(:work_package, project: project).tap do |grand|
  #    parent.update(parent: grand)
  #  end
  #end
  #let(:successor) do
  #  create(:work_package, project: project).tap do |suc|
  #    create(:follows_relation, from: suc, to: origin)
  #  end
  #end
  #let(:successor2) do
  #  create(:work_package, project: project).tap do |suc|
  #    create(:follows_relation, from: suc, to: origin)
  #  end
  #end
  #let(:successor_parent) do
  #  create(:work_package, project: project).tap do |par|
  #    successor.update(parent: par)
  #  end
  #end
  #let(:successor_child) do
  #  create(:work_package, project: project, parent: successor)
  #end
  #let(:successor_grandchild) do
  #  create(:work_package, project: project, parent: successor_child)
  #end
  #let(:successor_child2) do
  #  create(:work_package, project: project, parent: successor)
  #end
  #let(:successor_successor) do
  #  create(:work_package, project: project).tap do |suc|
  #    create(:follows_relation, from: suc, to: successor)
  #  end
  #end
  #let(:parent_successor) do
  #  create(:work_package, project: project).tap do |suc|
  #    create(:follows_relation, from: suc, to: parent)
  #  end
  #end
  #let(:parent_successor_parent) do
  #  create(:work_package, project: project).tap do |par|
  #    parent_successor.update(parent: par)
  #  end
  #end
  #let(:parent_successor_child) do
  #  create(:work_package, project: project, parent: parent_successor)
  #end
  #let(:blocker) do
  #  create(:work_package, project: project).tap do |blo|
  #    create(:relation, relation_type: 'blocks', from: blo, to: origin)
  #  end
  #end
  #let(:includer) do
  #  create(:work_package, project: project).tap do |inc|
  #    create(:relation, relation_type: 'includes', from: inc, to: origin)
  #  end
  #end
  let(:existing_work_packages) { [] }

  let(:relation_type) { Relation::TYPE_FOLLOWS }

  subject(:relatable) { WorkPackage.relatable(origin, relation_type) }

  it 'is an AR scope' do
    expect(relatable)
      .to be_a ActiveRecord::Relation
  end

  context 'for an unpersisted work package' do
    let(:origin) { WorkPackage.new }
    let!(:existing_work_packages) { [unrelated_work_package] }

    it 'contains every other work package' do
      expect(relatable)
        .to match_array([unrelated_work_package])
    end
  end

  context 'with a completely unrelated work package' do
    let!(:existing_work_packages) { [unrelated_work_package] }

    Relation::TYPES.each_key do |current_type|
      context "for the '#{current_type}' type" do
        let(:relation_type) { current_type }

        it 'contains the unrelated_work_package' do
          expect(relatable)
            .to match_array([unrelated_work_package])
        end
      end
    end

    context "for the '#{Relation::TYPE_HIERARCHY}'" do
      let(:relation_type) { Relation::TYPE_HIERARCHY }

      it 'contains the unrelated_work_package' do
        expect(relatable)
          .to match_array([unrelated_work_package])
      end
    end
  end

  context 'with a directly related work package' do
    let!(:existing_work_packages) { [directly_related_work_package] }

    Relation::TYPES.each_key do |current_type|
      context "with the existing relation and the queried being '#{current_type}' typed" do
        let(:relation_type) { current_type }

        it 'is empty' do
          expect(relatable)
            .to be_empty
        end
      end
    end
  end

  context 'with a parent and a sibling' do
    let!(:existing_work_packages) { [parent, sibling] }

    Relation::TYPES.each_key do |current_type|
      context "for the '#{current_type}' type" do
        let(:relation_type) { current_type }

        it 'contains the sibling' do
          expect(relatable)
            .to match_array([sibling])
        end
      end
    end
  end

  context 'with a transitively related work package' do
    let!(:existing_work_packages) { [directly_related_work_package, transitively_related_work_package] }

    context "for a 'follows' relation and the existing relations being in the same direction" do
      it 'contains the transitively related work package' do
        expect(relatable)
          .to match_array([transitively_related_work_package])
      end
    end

    context "for a 'follows' relation and the existing relations being in the opposite direction" do
      let(:directly_related_work_package_type) { Relation::TYPE_PRECEDES }
      let(:transitively_related_work_package_type) { Relation::TYPE_PRECEDES }

      it 'is empty' do
        expect(relatable)
          .to be_empty
      end
    end

    context "for a 'precedes' relation and the existing relations being in the opposite direction" do
      let(:relation_type) { Relation::TYPE_PRECEDES }
      let(:directly_related_work_package_type) { Relation::TYPE_FOLLOWS }
      let(:transitively_related_work_package_type) { Relation::TYPE_FOLLOWS }

      it 'is empty' do
        expect(relatable)
          .to be_empty
      end
    end

    context "for a 'related' relation and the existing relations being in the opposite direction" do
      let(:relation_type) { Relation::TYPE_RELATES }
      let(:directly_related_work_package_type) { Relation::TYPE_RELATES }
      let(:transitively_related_work_package_type) { Relation::TYPE_RELATES }

      # Switching the origin for transitively_related_work_package here since it would be more
      # complicated to switch around the relations
      subject(:relatable) { WorkPackage.relatable(transitively_related_work_package, relation_type) }

      it 'is empty' do
        expect(relatable)
          .to match_array [origin]
      end
    end
  end

  context "with a child" do
    let(:origin_child) do
      create(:work_package, project: project).tap do |par|
        origin.update(parent: par)
      end
    end
    let!(:existing_work_packages) { [origin_child] }

    Relation::TYPES.each_key do |current_type|
      context "for a '#{current_type}' type" do
        let(:relation_type) { current_type }

        it 'is empty' do
          expect(relatable)
            .to be_empty
        end
      end
    end
  end

  context "with two parent child pairs connected by a relation" do
    let(:origin_child) do
      create(:work_package, project: project).tap do |par|
        origin.update(parent: par)
      end
    end
    let(:other_parent) do
      create(:work_package, project: project)
    end
    let(:other_child) do
      create(:work_package, project: project, parent: other_parent).tap do |wp|
        create(:relation, from: wp, to: origin_child, relation_type: other_relation_type)
      end
    end
    let!(:existing_work_packages) { [origin_child, other_parent, other_child] }

    context "for a 'follows' and the existing relation being a follows in the opposite direction" do
      let(:other_relation_type) { Relation::TYPE_FOLLOWS }
      let(:relation_type) { Relation::TYPE_FOLLOWS }

      it 'is empty' do
        expect(relatable)
          .to be_empty
      end
    end

    context "for a 'follows' and the existing relation being a follows in the same direction" do
      # Using precedes will lead to the relation being reversed
      let(:other_relation_type) { Relation::TYPE_PRECEDES }
      let(:relation_type) { Relation::TYPE_FOLLOWS }

      it 'contains the work packages in the other hierarchy' do
        expect(relatable)
          .to match_array [other_parent, other_child]
      end
    end
  end


  # TODO: properly test all the cases
  # * work package related to another which has a parent and a sibling -> sibling to be selectable

  #context 'for an empty array' do
  #  it 'is empty' do
  #    expect(WorkPackage.for_scheduling([]))
  #      .to be_empty
  #  end
  #end

  #context 'for a work package with a predecessor' do
  #  let!(:existing_work_packages) { [predecessor] }

  #  it 'is empty' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to be_empty
  #  end
  #end

  #context 'for a work package with a parent' do
  #  let!(:existing_work_packages) { [parent] }

  #  it 'consists of the parent' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to match_array([parent])
  #  end
  #end

  #context 'for a work package with a successor' do
  #  let!(:existing_work_packages) { [successor] }

  #  it 'consists of the successor' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to match_array([successor])
  #  end
  #end

  #context 'for a work package with a blocking work package' do
  #  let!(:existing_work_packages) { [blocker] }

  #  it 'is empty' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to be_empty
  #  end
  #end

  #context 'for a work package with an including work package' do
  #  let!(:existing_work_packages) { [includer] }

  #  it 'is empty' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to be_empty
  #  end
  #end

  #context 'for a work package with a successor which has parent and child' do
  #  let!(:existing_work_packages) { [successor, successor_child, successor_parent] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of the successor, its child and parent' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_parent])
  #    end
  #  end

  #  context 'with successor scheduled manually' do
  #    before do
  #      successor.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end

  #  context 'with the successor\'s parent scheduled manually' do
  #    before do
  #      successor_parent.update_column(:schedule_manually, true)
  #    end

  #    it 'consists of the successor and its child' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child])
  #    end
  #  end

  #  context 'with successor\'s child scheduled manually' do
  #    before do
  #      successor_child.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
  #end

  #context 'for a work package with a successor which has parent and child and a successor of its own which is also a child of parent' do
  #  let!(:existing_work_packages) { [successor, successor_child, successor_parent, successor_successor] }

  #  before do
  #    create(:hierarchy_relation, from: successor_parent, to: successor_successor)
  #  end

  #  context 'with all scheduled automatically' do
  #    it 'consists of the successor, its child and parent and the successor successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_parent, successor_successor])
  #    end
  #  end

  #  context 'with successor parent scheduled manually' do
  #    before do
  #      successor_parent.update_column(:schedule_manually, true)
  #    end

  #    it 'consists of the successor, its child and successor successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_successor])
  #    end
  #  end

  #  context 'with successor\'s child scheduled manually' do
  #    before do
  #      successor_child.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
  #end

  #context 'for a work package with a successor which has parent and the parent has a follows relationship itself' do
  #  let!(:existing_work_packages) { [successor, successor_parent] }

  #  before do
  #    create(:follows_relation, from: successor_parent, to: origin)
  #  end

  #  context 'with all scheduled automatically' do
  #    it 'consists of the successor, its child and parent' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_parent])
  #    end
  #  end

  #  context 'with successor scheduled manually' do
  #    before do
  #      successor.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty (hierarchy over relationships)' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end

  #  context 'with the successor\'s parent scheduled manually' do
  #    before do
  #      successor_parent.update_column(:schedule_manually, true)
  #    end

  #    it 'consists of the successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor])
  #    end
  #  end

  #  context 'both scheduled manually' do
  #    before do
  #      successor.update_column(:schedule_manually, true)
  #      successor_parent.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
  #end

  #context 'for a work package with a successor with two children and the successor having a successor' do
  #  let!(:existing_work_packages) { [successor, successor_child, successor_child2, successor_successor] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of the successor, its child and the successor˚s successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_child2, successor_successor])
  #    end
  #  end

  #  context 'with one of the successor`s children scheduled manually' do
  #    before do
  #      successor_child2.update_column(:schedule_manually, true)
  #    end

  #    it 'consists of the successor, its automatically scheduled child and the successor˚s successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor_child, successor, successor_successor])
  #    end
  #  end

  #  context 'with both of the successor`s children scheduled manually' do
  #    before do
  #      successor_child.update_column(:schedule_manually, true)
  #      successor_child2.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
  #end

  #context 'for a work package with a parent and grandparent' do
  #  let!(:existing_work_packages) { [parent, grandparent] }

  #  it 'consists of the parent, grandparent' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to match_array([parent, grandparent])
  #  end
  #end

  #context 'for a work package with a parent which has a successor' do
  #  let!(:existing_work_packages) { [parent, parent_successor] }

  #  it 'consists of the parent, parent successor' do
  #    expect(WorkPackage.for_scheduling([origin]))
  #      .to match_array([parent, parent_successor])
  #  end
  #end

  #context 'for a work package with a parent which has a successor which has parent and child' do
  #  let!(:existing_work_packages) { [parent, parent_successor, parent_successor_child, parent_successor_parent] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of the parent, self and the whole parent successor hierarchy' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([parent, parent_successor, parent_successor_parent, parent_successor_child])
  #    end
  #  end

  #  context 'with the parent successor scheduled manually' do
  #    before do
  #      parent_successor.update_column(:schedule_manually, true)
  #    end

  #    it 'consists of the parent' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([parent])
  #    end
  #  end

  #  context 'with the parent scheduled manually' do
  #    before do
  #      parent.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end

  #  context 'with the parent successor\'s child scheduled manually' do
  #    before do
  #      parent_successor_child.update_column(:schedule_manually, true)
  #    end

  #    it 'contains the parent and self' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([parent])
  #    end
  #  end
  #end

  #context 'for a work package with a successor that has a successor' do
  #  let!(:existing_work_packages) { [successor, successor_successor] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of both successors' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_successor])
  #    end
  #  end

  #  context 'with the successor scheduled manually' do
  #    before do
  #      successor.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end

  #  context 'with the successor\'s successor scheduled manually' do
  #    before do
  #      successor_successor.update_column(:schedule_manually, true)
  #    end

  #    it 'contains the successor' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor])
  #    end
  #  end
  #end

  #context 'for a work package with a successor that has a child and grandchild' do
  #  let!(:existing_work_packages) { [successor, successor_child, successor_grandchild] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of both successors' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_grandchild])
  #    end
  #  end

  #  context 'with the successor\'s child scheduled manually' do
  #    before do
  #      successor_child.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
  #end

  #context 'for a work package with a successor that has a child and two grandchildren' do
  #  let(:successor_grandchild2) do
  #    create(:work_package, project: project, parent: successor_child)
  #  end

  #  let!(:existing_work_packages) { [successor, successor_child, successor_grandchild, successor_grandchild2] }

  #  context 'with all scheduled automatically' do
  #    it 'consists of the successor with its descendants' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_grandchild, successor_grandchild2])
  #    end
  #  end

  #  context 'with one of the successor\'s grandchildren scheduled manually' do
  #    before do
  #      successor_grandchild.update_column(:schedule_manually, true)
  #    end

  #    it 'contains the successor and the non automatically scheduled descendants' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to match_array([successor, successor_child, successor_grandchild2])
  #    end
  #  end

  #  context 'with both of the successor\'s grandchildren scheduled manually' do
  #    before do
  #      successor_grandchild.update_column(:schedule_manually, true)
  #      successor_grandchild2.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end

  #  context 'with the successor\'s child scheduled manually' do
  #    before do
  #      successor_child.update_column(:schedule_manually, true)
  #    end

  #    it 'is empty' do
  #      expect(WorkPackage.for_scheduling([origin]))
  #        .to be_empty
  #    end
  #  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
