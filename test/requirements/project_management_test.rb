# frozen_string_literal: true

require_relative '../test_helper'

class ProjectManagementTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
  end

  def test_finds_project_by_exact_name
    project = create_test_project(name: 'Mushroom')
    
    found = TimelogBot::Models::Project.find_by_name('Mushroom')
    
    assert_equal project.id, found.id
  end

  def test_finds_project_case_insensitive
    project = create_test_project(name: 'Mushroom')
    
    found = TimelogBot::Models::Project.find_by_name('mushroom')
    
    assert_equal project.id, found.id
  end

  def test_find_or_create_creates_new_project
    assert_equal 0, TimelogBot::Models::Project.count
    
    project = TimelogBot::Models::Project.find_or_create_by_name('New Project')
    
    assert_equal 1, TimelogBot::Models::Project.count
    assert_equal 'New Project', project.name
  end

  def test_find_or_create_returns_existing_project
    existing = create_test_project(name: 'Existing')
    
    found = TimelogBot::Models::Project.find_or_create_by_name('existing')
    
    assert_equal existing.id, found.id
    assert_equal 1, TimelogBot::Models::Project.count
  end

  def test_all_names_returns_project_names
    create_test_project(name: 'Alpha')
    create_test_project(name: 'Beta')
    create_test_project(name: 'Gamma')
    
    names = TimelogBot::Models::Project.all_names
    
    assert_equal 3, names.length
    assert_includes names, 'Alpha'
    assert_includes names, 'Beta'
    assert_includes names, 'Gamma'
  end

  def test_project_name_is_unique
    create_test_project(name: 'Unique')
    
    suppress_logging do
      assert_raises Sequel::UniqueConstraintViolation do
        create_test_project(name: 'Unique')
      end
    end
  end

  def test_project_has_many_time_entries
    project = create_test_project(name: 'TestProject')
    user = create_test_user
    
    create_test_time_entry(user: user, project: project, minutes: 60)
    create_test_time_entry(user: user, project: project, minutes: 120)
    
    entries = project.time_entries
    
    assert_equal 2, entries.length
  end
end
