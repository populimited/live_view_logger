# LiveViewLogger

Telemetry-driven logger for Phoenix LiveView lifecycle events. One log line
per navigation and per live event, with action, filtered params, user,
resource, status, outcome and duration.

## Installation

```elixir
def deps do
  [
    {:live_view_logger, github: "populimited/live_view_logger"}
  ]
end
```

The only dependency is `:telemetry`. It never queries the database and adds
no process to your supervision tree — it attaches telemetry handlers.

## Setup

Attach in your application supervisor, in `start/2`:

```elixir
:ok = Vox.Loggers.LiveView.attach()
```

### Options

* `:filtered_params` - param key names masked as `"[FILTERED]"` in the log.
  Matching is case-insensitive substring based, so `"password"` also masks
  `"password_confirmation"`. Defaults to `[]`, meaning no filtering.

```elixir
:ok =
  Vox.Loggers.LiveView.attach(
    filtered_params: ["password", "secret", "token"],
    user_fields: [:provider_id]
  )
```

* `:user_fields` - fields of `socket.assigns.current_user` logged next to
  `user_id` as `field=value`. Defaults to `[]`.

Pass the list yourself — the library knows nothing about Phoenix config.
If you use Phoenix's `config :phoenix, :filter_parameters`, be aware that
Phoenix rewrites that value into a compiled matcher tuple at boot, so it
cannot be read back as a list. Keep your own key list (for example under
`config :my_app, :log_filtered_params`) and pass it here.

## What gets logged

A single line per `handle_params` and `handle_event` invocation, plus
`mount` exceptions:

```
LiveView action=wave_web.root.company.edit user_id=1 provider_id=4 schema=Company company_id=1 status=ok outcome=re-rendered duration=1.7ms
  Parameters: %{"id" => "1"}
```

| Field | Meaning |
|---|---|
| `action` | view path plus event name or `live_action`, snake cased: module `WaveWeb.Root.CompanyLive.Form` with `live_action: :edit` becomes `wave_web.root.company.edit`; a `handle_event "save"` becomes `wave_web.root.company.save` |
| `Parameters:` | the raw params on their own indented line, with `:filtered_params` masked |
| `user_id` | id of `socket.assigns.current_user`, followed by the fields listed in `:user_fields` as `field=value` |
| `schema` | schema name of the record under the module's `:record` assign (see below), e.g. `Company` |
| `<schema>_id` | id of that record, named after the schema (`company_id`), falling back to `params["id"] as `resource_id` when no `:record` is set |
| `status` | `ok` or `error` (on telemetry `:exception` events) |
| `outcome` | redirect target on redirect, `redirected` without a target, `re-rendered` when assigns changed, `no-change` otherwise, `error` on exceptions |
| `duration` | handler duration in ms |

Deliberately not logged:

* `mount` stop - `handle_params` always runs right after mount on a routed
  LiveView, so it would duplicate the line.
* disconnected invocations - on a full page load LiveView renders twice
  (once during the HTTP render, once over the websocket); the disconnected
  run would duplicate the connected one. Only connected invocations log.

## Per-module configuration

By default every `handle_event` is logged. Two options are set per LiveView
module, either with the `use` macro:

```elixir
defmodule MyAppWeb.CompanyLive.Form do
  use Phoenix.LiveView
  use Vox.Loggers.LiveView, skip_events: ["validate"], record: :company
end
```

or by implementing the optional `logger_opts/0` callback directly:

```elixir
defmodule MyAppWeb.CompanyLive.Form do
  @behaviour Vox.Loggers.LiveView

  def logger_opts, do: [skip_events: ["validate"], record: :company]
end
```

### Options

* `:skip_events` - list of event names (`handle_event` first argument) that
  are never logged.
* `:record` - name of the assigns key holding the loaded resource, for
  example `:company` when the view assigns the schema as
  `assigns.company`. The struct's `:id` is the preferred `resource_id` and
  its schema name is logged as `schema=` (e.g. `Company`) and its id as `<schema_name>_id` (e.g. `company_id`); params `"id"` is the fallback, logged as `resource_id`.
  Without `:record`, no `resource` is logged and `resource_id` comes from
  params only.

Both options are per module only — they cannot be set globally via
`attach/1`.

## Running the tests

```sh
mix test
```
