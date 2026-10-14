defmodule Vox.Loggers.LiveView do
  @moduledoc """
  Telemetry-driven logger for Phoenix LiveView lifecycle events.

  Attach in your application supervisor:

      :ok = Vox.Loggers.LiveView.attach(filter_keys: ["password"])

  Logs `mount`, `handle_params` and `handle_event` stop/exception events as a
  single line with action, filtered params, user, status, outcome and duration.

  ## Per-module configuration

  By default every `handle_event` is logged. A LiveView module can skip
  specific events by declaring the `logger_opts/0` callback. Easiest via
  `use`:

      defmodule VoxWeb.UserLive.Index do
        use Phoenix.LiveView
        use Vox.Loggers.LiveView, skip_events: ["validate", "filter"], record: :user
      end

  * `:skip_events` - event names never logged.
  * `:record` - name of the assigns key holding the loaded resource. Its
    `:id` is the preferred `resource_id`; params `"id"` is the fallback.

  These options are per module only and cannot be set globally via
  `attach/1`. The callback can also be implemented directly:

      defmodule VoxWeb.UserLive.Index do
        @behaviour Vox.Loggers.LiveView
        def logger_opts, do: [skip_events: ["validate"]]
      end
  """

  require Logger

  @handler_prefix :"vox-liveview-logger"

  @doc """
  Per-module logger opts. See the module documentation.
  """
  @callback logger_opts() :: keyword()

  @optional_callbacks logger_opts: 0

  @doc """
  Declares the `logger_opts/0` callback with the given opts.

      use Vox.Loggers.LiveView, skip_events: ["validate"]
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Vox.Loggers.LiveView

      @doc false
      def logger_opts, do: unquote(opts)
    end
  end

  @events [
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :mount, :exception],
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_params, :exception],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :handle_event, :exception]
  ]

  @doc """
  Attaches the telemetry handlers.

  ## Options

    * `:filter_keys` - param key names to mask as `"[FILTERED]"` in the log.
      Matching is case-insensitive substring based (`"password"` masks
      `"password_confirmation"`). Defaults to `[]`, meaning no filtering.

  `:skip_events` and `:record` can only be set per module, via
  `logger_opts/0`.
  """
  def attach(opts \\ []) do
    Enum.each(@events, fn event ->
      handler_id = {@handler_prefix, event}
      _ = :telemetry.detach(handler_id)
      :ok = :telemetry.attach(handler_id, event, &__MODULE__.handle_event/4, opts)
    end)

    :ok
  end

  @doc false
  def handle_event([:phoenix, :live_view, action, status], measurements, metadata, config) do
    handle_log!(action, status, measurements, metadata, config)
  rescue
    e ->
      Logger.error(
        "LiveView logger skipped one event: " <> Exception.format(:error, e, __STACKTRACE__)
      )
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp handle_log!(fun, status, measurements, metadata, config) do
    socket = Map.get(metadata, :socket)
    assigns = socket.assigns
    opts = Keyword.merge(config, view_opts(socket.view))

    status_label = if status == :stop, do: "status=ok", else: "status=error"
    return_outcome = return_outcome(socket, fun, status)

    if metadata[:event] not in Keyword.get(opts, :skip_events, []) and assigns[:live_action] do
      {action, resource_id} = build_action(socket, assigns, metadata, opts)

      log!(
        action,
        filter_params(metadata[:params], opts),
        assigns[:current_user],
        resource_id,
        status_label,
        return_outcome,
        duration_ms(measurements[:duration])
      )
    end
  end

  defp view_opts(view) do
    if Code.ensure_loaded?(view) and function_exported?(view, :logger_opts, 0) do
      view.logger_opts()
    else
      []
    end
  end

  defp build_action(socket, assigns, metadata, opts) do
    view_name = "#{socket.view}"

    resource =
      view_name
      |> String.replace("Elixir.", "")
      |> String.replace("Live", "")
      |> String.downcase()
      |> String.split(".")
      |> Enum.drop(-1)

    resource_id =
      assigns_record_id(assigns, Keyword.get(opts, :record)) ||
        get_in(metadata, [:params, "id"])

    action = Enum.join(resource, ".")

    suffix =
      if is_nil(metadata[:event]),
        do: assigns[:live_action],
        else: metadata[:event]

    action =
      [action, suffix]
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.join(".")

    {action, resource_id}
  end

  defp assigns_record_id(_assigns, nil), do: nil

  defp assigns_record_id(assigns, key) do
    case Map.get(assigns, key) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp log!(
         action,
         params,
         user,
         resource_id,
         status,
         return_outcome,
         duration
       ) do
    user = if user, do: "user=#{user.id} (#{user.email})"
    action = if action, do: "action=#{action}"
    params = if params, do: "params=#{params}"
    resource_id = if resource_id, do: "resource_id=#{resource_id}"
    duration = if duration, do: "duration=#{duration}ms"
    return_outcome = if return_outcome, do: "outcome=#{return_outcome}"

    Logger.info(
      "LiveView #{action} #{params} #{user} #{resource_id} #{status} #{return_outcome} #{duration}"
    )
  end

  defp return_outcome(_socket, _fun, :exception), do: "error"

  defp return_outcome(%{redirected: {_env, _kind, %{to: redirect}}}, _fun, :stop)
       when not is_nil(redirect),
       do: redirect

  defp return_outcome(%{redirected: redirected}, _fun, :stop) when not is_nil(redirected),
    do: "redirected"

  defp return_outcome(%{assigns: %{__changed__: changed}}, _fun, :stop)
       when is_map(changed) and map_size(changed) > 0,
       do: "re-rendered"

  defp return_outcome(_socket, _fun, :stop), do: "no-change"

  defp return_outcome(_socket, _fun, _status), do: nil

  # Params

  defp filter_params(nil, _filter_keys), do: nil

  defp filter_params(params, opts) do
    params
    |> filter_values(filter_keys(opts))
    |> inspect(limit: :infinity, printable_limit: 2000)
  end

  defp filter_keys(opts),
    do: opts |> Keyword.get(:filter_keys, []) |> Enum.map(&String.downcase/1)

  defp filter_values(%module{} = struct, _keys) when is_atom(module), do: struct

  defp filter_values(%{} = map, keys) do
    Map.new(map, fn {key, value} -> {key, filter_value(key, value, keys)} end)
  end

  defp filter_values(list, keys) when is_list(list), do: Enum.map(list, &filter_values(&1, keys))

  defp filter_values(other, _keys), do: other

  defp filter_value(key, value, keys) do
    if key_match?(key, keys), do: "[FILTERED]", else: filter_values(value, keys)
  end

  defp key_match?(key, keys) when is_binary(key) do
    downcased = String.downcase(key)
    Enum.any?(keys, &String.contains?(downcased, &1))
  end

  defp key_match?(key, keys) when is_atom(key), do: key_match?(Atom.to_string(key), keys)
  defp key_match?(_key, _keys), do: false

  # Duration

  defp duration_ms(nil), do: 0.0

  defp duration_ms(duration_native) do
    duration_native
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
    |> Float.round(1)
  end
end
