defmodule VoxWeb.UserLive.Index do
end

defmodule VoxWeb.UserLive.Settings do
  @behaviour Vox.Loggers.LiveView

  def logger_opts, do: [skip_events: ["purge"]]
end

defmodule VoxWeb.UserLive.Form do
  use Vox.Loggers.LiveView, skip_events: ["save"]
end

defmodule VoxWeb.UserLive.Show do
  use Vox.Loggers.LiveView, record: :company
end

defmodule Vox.Loggers.LiveViewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vox.Loggers.LiveView

  setup do
    on_exit(fn ->
      events = [
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :mount, :exception],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :handle_params, :exception],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :handle_event, :exception]
      ]

      Enum.each(events, fn event ->
        _ = :telemetry.detach({:"vox-liveview-logger", event})
      end)
    end)

    :ok
  end

  describe "attach/1" do
    test "returns :ok and logs emitted events" do
      assert :ok = LiveView.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:phoenix, :live_view, :handle_params, :stop],
            %{duration: native_us(1_500)},
            %{socket: socket(%{live_action: :index}), params: %{}}
          )
        end)

      assert log =~ "action=voxweb.user.index"
      assert log =~ "status=ok"
    end

    test "does not subscribe to mount stop" do
      assert :ok = LiveView.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:phoenix, :live_view, :mount, :stop],
            %{duration: native_us(1_500)},
            %{socket: socket(%{live_action: :index}), params: %{}}
          )
        end)

      assert log == ""
    end

    test "uses the live_action as suffix when no event is given" do
      assert :ok = LiveView.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:phoenix, :live_view, :handle_params, :stop],
            %{duration: native_us(1_500)},
            %{socket: socket(%{live_action: :edit}), params: %{}}
          )
        end)

      assert log =~ "action=voxweb.user.edit"
    end
  end

  describe "handle_event/4" do
    test "logs action, params, user, status, outcome and duration" do
      metadata = %{
        socket: socket(%{live_action: :index, current_user: %{id: 7, email: "u@x.io"}}),
        event: "save",
        params: %{"id" => "3"}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_512)}, metadata)
        end)

      assert log =~ "action=voxweb.user.save"
      assert log =~ "resource_id=3"
      assert log =~ "params=%{\"id\" => \"3\"}"
      assert log =~ "user=7 (u@x.io)"
      assert log =~ "status=ok"
      assert log =~ "outcome=no-change"
      assert log =~ "duration=1.5ms"
    end

    test "does not fall back to assigns without a :record opt" do
      metadata = %{socket: socket(%{live_action: :edit, record: %{id: 42}}), params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "action=voxweb.user.edit"
      refute log =~ "resource_id="
    end

    test "uses the :record assigns key as resource_id fallback" do
      metadata = %{
        socket: socket_for(VoxWeb.UserLive.Show, :edit, %{company: %{id: 42}}),
        params: %{}
      }

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "action=voxweb.user.edit"
      assert log =~ "resource_id=42"
    end

    test "prefers the :record assigns over the params id" do
      metadata = %{
        socket: socket_for(VoxWeb.UserLive.Show, :edit, %{company: %{id: 42}}),
        params: %{"id" => "99"}
      }

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "resource_id=42"
      refute log =~ "resource_id=99"
    end

    test "logs validate events by default" do
      metadata = %{socket: socket(%{live_action: :index}), event: "validate", params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "action=voxweb.user.validate"
    end

    test "skips sockets without a live_action" do
      metadata = %{socket: socket(), params: %{}}

      log =
        capture_log(fn ->
          emit(:mount, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      refute log =~ "LiveView action="
    end

    test "logs status=error and outcome=error on exception" do
      metadata = %{socket: socket(%{live_action: :index}), params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_event, :exception, %{}, metadata)
        end)

      assert log =~ "status=error"
      assert log =~ "outcome=error"
    end

    test "logs the redirect target when the socket redirected" do
      sock =
        Map.put(socket(%{live_action: :index}), :redirected, {:live, :push, %{to: "/companies"}})

      metadata = %{socket: sock, params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "outcome=/companies"
    end

    test "logs outcome=redirected on a redirect without a to" do
      sock = Map.put(socket(%{live_action: :index}), :redirected, {:redirect, %{to: nil}})
      metadata = %{socket: sock, params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "outcome=redirected"
    end

    test "logs outcome=re-rendered on changed assigns" do
      metadata = %{
        socket: socket(%{live_action: :index, __changed__: %{company: true}}),
        params: %{}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "outcome=re-rendered"
    end

    test "masks params matching :filter_keys" do
      metadata = %{
        socket: socket(%{live_action: :index}),
        params: %{"password" => "hunter2", "id" => "3"}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata,
            filter_keys: ["password"]
          )
        end)

      assert log =~ "params=%{\"id\" => \"3\", \"password\" => \"[FILTERED]\"}"
    end

    test "masks atom-keyed params and substrings of :filter_keys" do
      metadata = %{
        socket: socket(%{live_action: :index}),
        params: %{password_confirmation: "hunter2"}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata,
            filter_keys: ["PASSWORD"]
          )
        end)

      assert log =~ "params=%{password_confirmation: \"[FILTERED]\"}"
    end

    test "ignores non-list :filter_keys values" do
      metadata = %{socket: socket(%{live_action: :index}), params: %{"password" => "hunter2"}}

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata,
            filter_keys: {:compiled, :bogus}
          )
        end)

      assert log =~ "params=%{\"password\" => \"hunter2\"}"
    end

    test "logs params unfiltered without :filter_keys" do
      metadata = %{
        socket: socket(%{live_action: :index}),
        params: %{"password" => "hunter2"}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "params=%{\"password\" => \"hunter2\"}"
    end

    test "defaults duration to 0.0ms when missing" do
      metadata = %{socket: socket(%{live_action: :index}), params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_params, :stop, %{}, metadata)
        end)

      assert log =~ "duration=0.0ms"
    end

    test "does not raise on unexpected events" do
      assert :ok = LiveView.handle_event([:other, :event], %{}, %{}, %{})
    end
  end

  describe "per-module configuration" do
    test "skips events listed by a module implementing logger_opts/0" do
      metadata = %{
        socket: socket_for(VoxWeb.UserLive.Settings, :index),
        event: "purge",
        params: %{}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      refute log =~ "LiveView action="
    end

    test "still logs events not listed by the module" do
      metadata = %{
        socket: socket_for(VoxWeb.UserLive.Settings, :index),
        event: "save",
        params: %{}
      }

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      assert log =~ "action=voxweb.user.save"
    end

    test "skips events from a module using the macro" do
      metadata = %{socket: socket_for(VoxWeb.UserLive.Form, :index), event: "save", params: %{}}

      log =
        capture_log(fn ->
          emit(:handle_event, :stop, %{duration: native_us(1_500)}, metadata)
        end)

      refute log =~ "LiveView action="
    end
  end

  defp emit(action, status, measurements, metadata, opts \\ []) do
    LiveView.handle_event([:phoenix, :live_view, action, status], measurements, metadata, opts)
  end

  defp socket(assigns \\ %{}, view \\ VoxWeb.UserLive.Index) do
    %{
      view: view,
      assigns: Map.merge(%{__changed__: %{}}, Map.new(assigns)),
      redirected: nil
    }
  end

  defp socket_for(view, live_action, assigns \\ %{}) do
    socket(Map.merge(%{live_action: live_action}, assigns), view)
  end

  defp native_us(us), do: System.convert_time_unit(us, :microsecond, :native)
end
