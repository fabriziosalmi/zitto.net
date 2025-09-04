defmodule TheCollective.Evolution do
  @moduledoc """
  The Evolution Engine of The Collective.
  
  This module defines and monitors the milestones that The Collective
  can achieve as it grows and evolves. It checks for new achievements
  and triggers evolution events that are broadcast to all connected souls.
  """
  
  require Logger
  
  alias TheCollective.Redis
  alias TheCollectiveWeb.CollectiveChannel
  
  @doc """
  Defines all possible evolution milestones for The Collective.
  
  Each milestone has:
  - id: Unique identifier
  - type: :concurrent (based on simultaneous connections) or :time (based on total seconds)
  - threshold: The value that must be reached to unlock
  - name: Human-readable name
  - description: Description of what this milestone represents
  """
  def milestones do
    %{
      # Concurrent connection milestones
      "first_awakening" => %{
        id: "first_awakening",
        type: :concurrent,
        threshold: 1,
        name: "First Awakening",
        description: "The first soul joins The Collective"
      },
      "gathering" => %{
        id: "gathering",
        type: :concurrent,
        threshold: 10,
        name: "The Gathering",
        description: "Ten souls unite in silence"
      },
      "century_of_souls" => %{
        id: "century_of_souls",
        type: :concurrent,
        threshold: 100,
        name: "Century of Souls",
        description: "One hundred souls breathe as one"
      },
      "thousand_minds" => %{
        id: "thousand_minds",
        type: :concurrent,
        threshold: 1_000,
        name: "Thousand Minds",
        description: "A thousand minds in perfect unity"
      },
      "ten_thousand_strong" => %{
        id: "ten_thousand_strong",
        type: :concurrent,
        threshold: 10_000,
        name: "Ten Thousand Strong",
        description: "Ten thousand souls transcend individuality"
      },
      "hundred_thousand_symphony" => %{
        id: "hundred_thousand_symphony",
        type: :concurrent,
        threshold: 100_000,
        name: "Hundred Thousand Symphony",
        description: "A symphony of one hundred thousand silent voices"
      },
      "million_soul_consciousness" => %{
        id: "million_soul_consciousness",
        type: :concurrent,
        threshold: 1_000_000,
        name: "Million Soul Consciousness",
        description: "One million souls achieve collective consciousness"
      },
      
      # Time-based milestones
      "first_minute" => %{
        id: "first_minute",
        type: :time,
        threshold: 60,
        name: "First Minute",
        description: "Sixty seconds of collective existence"
      },
      "first_hour" => %{
        id: "first_hour",
        type: :time,
        threshold: 3_600,
        name: "First Hour",
        description: "One hour of accumulated consciousness"
      },
      "first_day" => %{
        id: "first_day",
        type: :time,
        threshold: 86_400,
        name: "First Day",
        description: "Twenty-four hours of collective experience"
      },
      "first_week" => %{
        id: "first_week",
        type: :time,
        threshold: 604_800,
        name: "First Week",
        description: "One week of shared silence"
      },
      "first_month" => %{
        id: "first_month",
        type: :time,
        threshold: 2_592_000,
        name: "First Month",
        description: "One month of collective evolution"
      },
      "first_year" => %{
        id: "first_year",
        type: :time,
        threshold: 31_536_000,
        name: "First Year",
        description: "One year of accumulated wisdom"
      },
      "century_of_experience" => %{
        id: "century_of_experience",
        type: :time,
        threshold: 3_153_600_000,
        name: "Century of Experience",
        description: "One hundred years of collective consciousness"
      },
      "millennium_of_silence" => %{
        id: "millennium_of_silence",
        type: :time,
        threshold: 31_536_000_000,
        name: "Millennium of Silence",
        description: "One thousand years of shared existence"
      },
      
      # Special compound milestones
      "sustained_thousand" => %{
        id: "sustained_thousand",
        type: :special,
        name: "Sustained Consciousness",
        description: "One thousand souls maintained for one hour",
        check_fn: &check_sustained_thousand/1
      },
      "peak_experience" => %{
        id: "peak_experience",
        type: :special,
        name: "Peak Experience",
        description: "Maximum concurrent souls reaches new heights",
        check_fn: &check_peak_experience/1
      }
    }
  end
  
  @doc """
  Check for new evolution milestones and trigger events.
  
  This function is called by Chronos after each time update to see
  if any new milestones have been achieved.
  """
  def check_for_evolution do
    current_state = get_current_state()
    check_milestones_with_state(current_state)
  end
  
  @doc """
  Check for milestones based on current concurrent connections.
  
  This function is called when a new connection joins to immediately
  check for milestone achievements based on the new connection count.
  """
  def check_milestones(concurrent_connections) do
    current_state = %{
      concurrent_connections: concurrent_connections,
      total_connection_seconds: Redis.get_int("global:total_connection_seconds")
    }
    
    check_milestones_with_state(current_state)
  end
  
  # Get details for a specific milestone by ID (public helper)
  def get_milestone_details(milestone_id) do
    Map.get(milestones(), milestone_id)
  end
  
  # Private helpers (no @doc to avoid warnings)
  defp check_milestones_with_state(current_state) do
    unlocked_milestones = get_unlocked_milestone_ids()

    milestones()
    |> Enum.each(fn {milestone_id, milestone} ->
      if not MapSet.member?(unlocked_milestones, milestone_id) do
        if milestone_reached?(milestone, current_state) do
          unlock_milestone(milestone)
        end
      end
    end)
  end

  defp get_current_state do
    %{
      concurrent_connections: Redis.get_int("global:concurrent_connections") || 0,
      total_connection_seconds: Redis.get_int("global:total_connection_seconds") || 0
    }
  end
  
  defp get_unlocked_milestone_ids do
    case Redis.smembers("global:unlocked_milestones") do
      {:ok, milestone_ids} when is_list(milestone_ids) -> MapSet.new(milestone_ids)
      _ -> MapSet.new()
    end
  end
  
  defp milestone_reached?(%{type: :concurrent, threshold: threshold}, state) do
    state.concurrent_connections >= threshold
  end
  
  defp milestone_reached?(%{type: :time, threshold: threshold}, state) do
    state.total_connection_seconds >= threshold
  end
  
  defp milestone_reached?(%{type: :special, check_fn: check_fn}, state) do
    check_fn.(state)
  end
  
  defp unlock_milestone(milestone) do
    Logger.info("EVOLUTION EVENT: #{milestone.name || milestone.id}")

    case Redis.sadd("global:unlocked_milestones", milestone.id) do
      {:ok, 1} ->
        Logger.info("Milestone #{milestone.id} unlocked")
        CollectiveChannel.broadcast_evolution_event(milestone)
      {:ok, 0} ->
        Logger.debug("Milestone #{milestone.id} already unlocked (race)")
      {:error, reason} ->
        Logger.error("Failed to store milestone #{milestone.id}: #{inspect(reason)}")
    end
  end
  
  defp check_sustained_thousand(state) do
    # This is a simplified check - in production you might want to track
    # the duration of high connection counts more precisely
    state.concurrent_connections >= 1000 and state.total_connection_seconds >= 3_600
  end
  
  defp check_peak_experience(state) do
    # Get the stored peak from Redis
    current_peak_connections = Redis.get_int("global:peak_connections") || 0
    
    if state.concurrent_connections > current_peak_connections do
      # Update the peak
      Redis.set("global:peak_connections", state.concurrent_connections)
      
      # Trigger milestone if this is a significant peak (every 10x increase)
      significant_peak_thresholds = [10, 100, 1_000, 10_000, 100_000, 1_000_000]
      Enum.any?(significant_peak_thresholds, fn threshold -> 
        state.concurrent_connections >= threshold and current_peak_connections < threshold
      end)
    else
      false
    end
  end
  
  @doc """
  Get evolution statistics for monitoring.
  """
  def get_evolution_stats do
    unlocked_count = 
      case Redis.smembers("global:unlocked_milestones") do
        {:ok, milestones} -> length(milestones)
        {:error, _} -> 0
      end
    
    total_milestones = map_size(milestones())
    current_state = get_current_state()
    
    %{
      unlocked_milestones: unlocked_count,
      total_milestones: total_milestones,
      progress_percentage: if(total_milestones > 0, do: (unlocked_count / total_milestones) * 100, else: 0),
      current_state: current_state
    }
  end
end
