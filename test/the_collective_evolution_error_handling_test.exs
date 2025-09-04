defmodule TheCollective.EvolutionErrorHandlingTest do
  @moduledoc """
  Tests for improved exception handling and null pointer protection in Evolution module.
  """
  
  use ExUnit.Case, async: false
  
  alias TheCollective.Evolution
  
  describe "check_milestones/1 parameter validation" do
    test "handles invalid connection counts" do
      # Should handle nil, negative, or non-integer values gracefully
      assert Evolution.check_milestones(nil) == :ok
      assert Evolution.check_milestones(-1) == :ok
      assert Evolution.check_milestones("invalid") == :ok
      assert Evolution.check_milestones(1.5) == :ok
    end
    
    test "handles valid connection counts" do
      # Should accept valid positive integers
      assert Evolution.check_milestones(0) == :ok
      assert Evolution.check_milestones(1) == :ok
      assert Evolution.check_milestones(100) == :ok
    end
  end
  
  describe "milestone system robustness" do
    test "milestone definitions are valid" do
      milestones = Evolution.milestones()
      
      # Verify milestones map is not empty and contains expected structure
      assert is_map(milestones)
      assert map_size(milestones) > 0
      
      # Check that each milestone has required fields
      for {_id, milestone} <- milestones do
        assert Map.has_key?(milestone, :id)
        assert Map.has_key?(milestone, :type)
        assert Map.has_key?(milestone, :name)
        assert Map.has_key?(milestone, :description)
      end
    end
    
    test "get_milestone_details handles invalid IDs" do
      assert Evolution.get_milestone_details(nil) == nil
      assert Evolution.get_milestone_details("nonexistent") == nil
      assert Evolution.get_milestone_details(123) == nil
    end
    
    test "get_milestone_details returns valid milestones" do
      milestone = Evolution.get_milestone_details("first_awakening")
      assert is_map(milestone)
      assert milestone.id == "first_awakening"
    end
  end
  
  describe "evolution statistics" do
    test "get_evolution_stats returns valid structure" do
      stats = Evolution.get_evolution_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :unlocked_milestones)
      assert Map.has_key?(stats, :total_milestones)
      assert Map.has_key?(stats, :progress_percentage)
      assert Map.has_key?(stats, :current_state)
      
      # Verify data types
      assert is_integer(stats.unlocked_milestones)
      assert is_integer(stats.total_milestones)
      assert is_number(stats.progress_percentage)
      assert is_map(stats.current_state)
    end
  end
end