# frozen_string_literal: true

require_relative '../test_helper'
require 'csv'

class TeamReportsTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
    ENV['REPORT_ADMINS'] = 'U_ADMIN_1,U_ADMIN_2'
  end

  def test_team_report_generates_csv
    user1 = create_test_user(slack_id: 'U111', username: 'alice')
    user2 = create_test_user(slack_id: 'U222', username: 'bob')
    project1 = create_test_project(name: 'Alpha')
    project2 = create_test_project(name: 'Beta')
    
    # January entries
    create_test_time_entry(user: user1, project: project1, minutes: 180, date: Date.new(2026, 1, 15))
    create_test_time_entry(user: user2, project: project1, minutes: 120, date: Date.new(2026, 1, 20))
    create_test_time_entry(user: user2, project: project2, minutes: 60, date: Date.new(2026, 1, 25))
    
    csv_content = TimelogBot::Services::ReportGenerator.team_report(month: Date.new(2026, 1, 1))
    
    refute_nil csv_content
    
    rows = CSV.parse(csv_content)
    
    # Header row: User, Projects..., Total
    assert_equal 'User', rows[0][0]
    assert_includes rows[0], 'Alpha'
    assert_includes rows[0], 'Beta'
    assert_equal 'Total', rows[0].last
    
    # User rows
    alice_row = rows.find { |r| r[0] == 'alice' }
    bob_row = rows.find { |r| r[0] == 'bob' }
    
    assert alice_row
    assert bob_row
    
    # Total row
    assert_equal 'TOTAL', rows.last[0]
  end

  def test_team_report_returns_nil_for_no_entries
    result = TimelogBot::Services::ReportGenerator.team_report(month: Date.new(2026, 1, 1))
    
    assert_nil result
  end

  def test_team_report_filters_by_month
    user = create_test_user(slack_id: 'U111', username: 'alice')
    project = create_test_project(name: 'Test')
    
    # January entry
    create_test_time_entry(user: user, project: project, minutes: 180, date: Date.new(2026, 1, 15))
    # February entry
    create_test_time_entry(user: user, project: project, minutes: 120, date: Date.new(2026, 2, 15))
    
    jan_report = TimelogBot::Services::ReportGenerator.team_report(month: Date.new(2026, 1, 1))
    feb_report = TimelogBot::Services::ReportGenerator.team_report(month: Date.new(2026, 2, 1))
    
    jan_rows = CSV.parse(jan_report)
    feb_rows = CSV.parse(feb_report)
    
    # January should have 3 hours
    alice_jan = jan_rows.find { |r| r[0] == 'alice' }
    assert_includes alice_jan, '3'
    
    # February should have 2 hours
    alice_feb = feb_rows.find { |r| r[0] == 'alice' }
    assert_includes alice_feb, '2'
  end

  def test_authorized_for_team_report_checks_admin_list
    handler = TimelogBot::Handlers::SlashCommandHandler
    
    assert handler.send(:authorized_for_team_report?, 'U_ADMIN_1')
    assert handler.send(:authorized_for_team_report?, 'U_ADMIN_2')
    refute handler.send(:authorized_for_team_report?, 'U_RANDOM')
  end

  def test_parse_month_argument_with_valid_format
    handler = TimelogBot::Handlers::SlashCommandHandler
    
    result = handler.send(:parse_month_argument, '2026-03')
    
    assert_equal 2026, result.year
    assert_equal 3, result.month
    assert_equal 1, result.day
  end

  def test_parse_month_argument_defaults_to_current_month
    handler = TimelogBot::Handlers::SlashCommandHandler
    
    result = handler.send(:parse_month_argument, '')
    
    assert_equal Date.today.year, result.year
    assert_equal Date.today.month, result.month
  end

  def test_parse_month_argument_handles_invalid_input
    handler = TimelogBot::Handlers::SlashCommandHandler
    
    result = suppress_logging do
      handler.send(:parse_month_argument, 'not-a-date')
    end
    
    # Should default to current month
    assert_equal Date.today.year, result.year
    assert_equal Date.today.month, result.month
  end
end
