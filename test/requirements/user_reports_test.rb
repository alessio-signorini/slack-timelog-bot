# frozen_string_literal: true

require_relative '../test_helper'
require 'csv'

class UserReportsTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
  end

  def test_user_report_generates_csv
    user = create_test_user(slack_id: 'U12345678', username: 'alice')
    project1 = create_test_project(name: 'Alpha')
    project2 = create_test_project(name: 'Beta')
    
    # January entries
    create_test_time_entry(user: user, project: project1, minutes: 180, date: Date.new(2026, 1, 15))
    create_test_time_entry(user: user, project: project2, minutes: 120, date: Date.new(2026, 1, 20))
    
    # February entries
    create_test_time_entry(user: user, project: project1, minutes: 60, date: Date.new(2026, 2, 10))
    
    csv_content = TimelogBot::Services::ReportGenerator.user_report(user_id: user.id)
    
    refute_nil csv_content
    
    rows = CSV.parse(csv_content)
    
    # Header row
    assert_equal 'Project', rows[0][0]
    assert_includes rows[0], 'Jan 2026'
    assert_includes rows[0], 'Feb 2026'
    assert_equal 'Total', rows[0].last
    
    # Data rows (sorted by project name)
    alpha_row = rows.find { |r| r[0] == 'Alpha' }
    beta_row = rows.find { |r| r[0] == 'Beta' }
    
    assert alpha_row
    assert beta_row
    
    # Total row
    assert_equal 'TOTAL', rows.last[0]
  end

  def test_user_report_returns_nil_for_no_entries
    user = create_test_user
    
    result = TimelogBot::Services::ReportGenerator.user_report(user_id: user.id)
    
    assert_nil result
  end

  def test_user_report_formats_hours_correctly
    user = create_test_user
    project = create_test_project(name: 'Test')
    
    create_test_time_entry(user: user, project: project, minutes: 90, date: Date.today)
    
    csv_content = TimelogBot::Services::ReportGenerator.user_report(user_id: user.id)
    rows = CSV.parse(csv_content)
    
    # Find the Test row
    test_row = rows.find { |r| r[0] == 'Test' }
    
    # Should show 1.5 (90 minutes = 1.5 hours)
    assert_includes test_row, '1.5'
  end

  def test_user_report_includes_all_months
    user = create_test_user
    project = create_test_project(name: 'Test')
    
    # Create entries in non-consecutive months
    create_test_time_entry(user: user, project: project, minutes: 60, date: Date.new(2026, 1, 1))
    create_test_time_entry(user: user, project: project, minutes: 60, date: Date.new(2026, 3, 1))
    create_test_time_entry(user: user, project: project, minutes: 60, date: Date.new(2026, 6, 1))
    
    csv_content = TimelogBot::Services::ReportGenerator.user_report(user_id: user.id)
    rows = CSV.parse(csv_content)
    
    # Header should include all months with entries
    header = rows[0]
    assert_includes header, 'Jan 2026'
    assert_includes header, 'Mar 2026'
    assert_includes header, 'Jun 2026'
    
    # Should NOT include months without entries
    refute_includes header, 'Feb 2026'
  end
end
