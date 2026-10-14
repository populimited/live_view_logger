# LiveViewLogger

Telemetry-driven logger for Phoenix LiveView lifecycle events, published as
the `Vox.Loggers.LiveView` module.

Attach in your application supervisor:

```elixir
:ok =
  Vox.Loggers.LiveView.attach(
    filter_keys: ["password"]
  )
```

Logs `mount`, `handle_params` and `handle_event` stop/exception events as a
single line:

```
LiveView action=root.company.save params=%{"company" => %{"name" => "Acme"}} user=1 (daniele@dev.com) resource_id=1 status=ok outcome=no-change duration=9.4ms
```

## Per-module configuration

`:skip_events` and `:record` are set per LiveView module via the `use` macro:

```elixir
defmodule VoxWeb.CompanyLive.Form do
  use Phoenix.LiveView
  use Vox.Loggers.LiveView, skip_events: ["validate"], record: :company
end
```

* `:skip_events` - event names never logged.
* `:record` - name of the assigns key holding the loaded resource. Its `:id`
  is the preferred `resource_id`; params `"id"` is the fallback.

## Installation

```elixir
def deps do
  [
    {:live_view_logger, github: "populimited/live_view_logger"}
  ]
end
```
