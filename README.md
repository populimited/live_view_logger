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

* `:filter_keys` - param key names masked as `"[FILTERED]"` in the log.
  Matching is case-insensitive substring based, so `"password"` also masks
  `"password_confirmation"`. Defaults to `[]`, meaning no filtering.

```elixir
:ok = Vox.Loggers.LiveView.attach(filter_keys: ["password", "secret", "token"])
```

Pass the list yourself — the library knows nothing about Phoenix config.
If you use Phoenix's `config :phoenix, :filter_parameters`, be aware that
Phoenix rewrites that value into a compiled matcher tuple at boot, so it
cannot be read back as a list. Keep your own key list (for example under
`config :my_app, :log_filter_keys`) and pass it here.

## What gets logged

A single line per `handle_params` and `handle_event` invocation, plus
`mount` exceptions:

```
LiveView action=wave_web.root.company.edit params=%{"id" => "1"} user=1 (daniele@dev.com) resource=Wave.Root.Company resource_id=1 status=ok outcome=re-rendered duration=1.7ms
```

| Field | Meaning |
|---|---|
| `action` | view path plus event name or `live_action`, snake cased: module `WaveWeb.Root.CompanyLive.Form` with `live_action: :edit` becomes `wave_web.root.company.edit`; a `handle_event "save"` becomes `wave_web.root.company.save` |
| `params` | the raw params, with `:filter_keys` masked |
| `user` | `id` and `email` of `socket.assigns.current_user` |
| `resource` | full schema struct name of the record under the module's `:record` assign (see below), e.g. `Wave.Root.Company` |
| `resource_id` | id of that record, falling back to `params["id"]` |
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
  its full struct name becomes `resource` (e.g. `Wave.Root.Company`); params `"id"` is the fallback.
  Without `:record`, no `resource` is logged and `resource_id` comes from
  params only.

Both options are per module only — they cannot be set globally via
`attach/1`.

## Running the tests

```sh
mix test
```
