import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/result

pub type Strategy {
  /// If one child process terminates and is to be restarted, only that child
  /// process is affected. This is the default restart strategy.
  OneForOne
}

pub type MaxChildren {
  Children(Int)
  Infinity
}

/// A supervisor can be configured to automatically shut itself down with exit
/// reason shutdown when significant children terminate with the auto_shutdown
/// key in the above map.
pub type AutoShutdown {
  /// Automic shutdown is disabled. This is the default and only setting
  /// for dynamic supervisors.
  ///
  /// With auto_shutdown set to never, child specs with the significant flag
  /// set to true are considered invalid and will be rejected.
  Never
}

pub opaque type Builder {
  Builder(
    strategy: Strategy,
    intensity: Int,
    period: Int,
    auto_shutdown: AutoShutdown,
    max_restarts: Int,
    max_seconds: Int,
    max_children: MaxChildren,
    children: List(ChildBuilder),
  )
}

pub fn new(strategy strategy: Strategy) -> Builder {
  Builder(
    strategy: strategy,
    intensity: 2,
    period: 5,
    auto_shutdown: Never,
    max_restarts: 1,
    max_seconds: 5,
    max_children: Infinity,
    children: [],
  )
}

/// To prevent a supervisor from getting into an infinite loop of child
/// process terminations and restarts, a maximum restart intensity is
/// defined using two integer values specified with keys intensity and
/// period in the above map. Assuming the values MaxR for intensity and MaxT
/// for period, then, if more than MaxR restarts occur within MaxT seconds,
/// the supervisor terminates all child processes and then itself. The
/// termination reason for the supervisor itself in that case will be
/// shutdown. 
///
/// Intensity defaults to 1 and period defaults to 5.
pub fn restart_tolerance(
  builder: Builder,
  intensity intensity: Int,
  period period: Int,
) -> Builder {
  Builder(..builder, intensity: intensity, period: period)
}

// TODO: Add functions to configure max_restarts, max_seconds, max_children

// TODO: then work that logic into the rest

// TODO: Compare with Elixir logic - do we reap the desired performance benefits due to starting them all in no particular order? 

/// A supervisor can be configured to automatically shut itself down with
/// exit reason shutdown when significant children terminate.
pub fn auto_shutdown(builder: Builder, value: AutoShutdown) -> Builder {
  Builder(..builder, auto_shutdown: value)
}

/// Restart defines when a terminated child process must be restarted. 
pub type Restart {
  /// A permanent child process is always restarted.
  Permanent
  /// A transient child process is restarted only if it terminates abnormally,
  /// that is, with another exit reason than `normal`, `shutdown`, or
  /// `{shutdown,Term}`.
  Transient
  /// A temporary child process is never restarted (even when the supervisor's
  /// restart strategy is `RestForOne` or `OneForAll` and a sibling's death
  /// causes the temporary process to be terminated).
  Temporary
}

pub type ChildType {
  Worker(
    /// The number of milliseconds the child is given to shut down. The
    /// supervisor tells the child process to terminate by calling
    /// `exit(Child,shutdown)` and then wait for an exit signal with reason
    /// shutdown back from the child process. If no exit signal is received
    /// within the specified number of milliseconds, the child process is
    /// unconditionally terminated using `exit(Child,kill)`.
    shutdown_ms: Int,
  )
  Supervisor
}

pub opaque type ChildBuilder {
  ChildBuilder(
    /// id is used to identify the child specification internally by the
    /// supervisor.
    ///
    /// Notice that this identifier on occations has been called "name". As far
    /// as possible, the terms "identifier" or "id" are now used but to keep
    /// backward compatibility, some occurences of "name" can still be found, for
    /// example in error messages.
    id: String,
    /// A function to call to start the child process.
    starter: fn() -> Result(Pid, Dynamic),
    /// When the child is to be restarted. See the `Restart` documentation for
    /// more.
    ///
    /// You most likely want the `Permanent` variant.
    restart: Restart,
    /// This defines if a child is considered significant for automatic
    /// self-shutdown of the supervisor.
    ///
    /// You most likely do not want to consider any children significant.
    ///
    /// This will be ignored if the supervisor auto shutdown is set to `Never`,
    /// which is the default.
    significant: Bool,
    /// Whether the child is a supervisor or not.
    child_type: ChildType,
  )
}

// [TODO]: potentially rework - init needed?
pub fn start_link(builder: Builder) -> Result(Pid, Dynamic) {
  let flags =
    dict.new()
    |> property("strategy", builder.strategy)
    |> property("intensity", builder.intensity)
    |> property("period", builder.period)
    |> property("auto_shutdown", builder.auto_shutdown)

  let children = builder.children |> list.reverse |> list.map(convert_child)

  erlang_start_link(#(flags, children))
}

@external(erlang, "gleam_otp_external", "static_supervisor_start_link")
fn erlang_start_link(
  args: #(Dict(Atom, Dynamic), List(Dict(Atom, Dynamic))),
) -> Result(Pid, Dynamic)

/// Add a child to the supervisor.
pub fn add(builder: Builder, child: ChildBuilder) -> Builder {
  Builder(..builder, children: [child, ..builder.children])
}

/// A regular child that is not also a supervisor.
///
/// id is used to identify the child specification internally by the
/// supervisor.
/// Notice that this identifier on occations has been called "name". As far
/// as possible, the terms "identifier" or "id" are now used but to keep
/// backward compatibility, some occurences of "name" can still be found, for
/// example in error messages.
///
pub fn worker_child(
  id id: String,
  run starter: fn() -> Result(Pid, whatever),
) -> ChildBuilder {
  ChildBuilder(
    id: id,
    starter: fn() { starter() |> result.map_error(dynamic.from) },
    significant: False,
    restart: Permanent,
    child_type: Worker(5000),
  )
}

/// A special child that is a supervisor itself.
///
/// id is used to identify the child specification internally by the
/// supervisor.
/// Notice that this identifier on occations has been called "name". As far
/// as possible, the terms "identifier" or "id" are now used but to keep
/// backward compatibility, some occurences of "name" can still be found, for
/// example in error messages.
///
pub fn supervisor_child(
  id id: String,
  run starter: fn() -> Result(Pid, whatever),
) -> ChildBuilder {
  ChildBuilder(
    id: id,
    starter: fn() { starter() |> result.map_error(dynamic.from) },
    restart: Permanent,
    significant: False,
    child_type: Supervisor,
  )
}

/// This defines the amount of milliseconds a child has to shut down before
/// being brutal killed by the supervisor.
///
/// If not set the default for a child is 5000ms.
///
/// This will be ignored if the child is a supervisor itself.
///
pub fn timeout(child: ChildBuilder, ms ms: Int) -> ChildBuilder {
  case child.child_type {
    Worker(_) -> ChildBuilder(..child, child_type: Worker(ms))
    _ -> child
  }
}

/// When the child is to be restarted. See the `Restart` documentation for
/// more.
///
/// The default value for restart is `Permenent`.
pub fn restart(child: ChildBuilder, restart: Restart) -> ChildBuilder {
  ChildBuilder(..child, restart: restart)
}

fn convert_child(child: ChildBuilder) -> Dict(Atom, Dynamic) {
  let mfa = #(
    atom.create_from_string("erlang"),
    atom.create_from_string("apply"),
    [dynamic.from(child.starter), dynamic.from([])],
  )

  let #(type_, shutdown) = case child.child_type {
    Supervisor -> #(
      atom.create_from_string("supervisor"),
      dynamic.from(atom.create_from_string("infinity")),
    )
    Worker(timeout) -> #(
      atom.create_from_string("worker"),
      dynamic.from(timeout),
    )
  }

  dict.new()
  |> property("id", child.id)
  |> property("start", mfa)
  |> property("restart", child.restart)
  |> property("type", type_)
  |> property("shutdown", shutdown)
}

// [TODO]: Check, whether a phantom / oblique type combination might fit better
pub type Message(child) {
  StartChild(child)
  TerminateChild(child)
  CountChildren
  WhichChildren
  Shutdown
}

fn handle_message(message: Message(e)) {
  todo
}

fn property(
  dict: Dict(Atom, Dynamic),
  key: String,
  value: anything,
) -> Dict(Atom, Dynamic) {
  dict.insert(dict, atom.create_from_string(key), dynamic.from(value))
}

@external(erlang, "gleam_otp_external", "put_dynamic_supervisor_initial_call")
fn put_initial_call() -> Dynamic

// [TODO]: Continue
@internal
pub fn init() {
  put_initial_call()
  process.trap_exits(True)

  let state = dict.new()
  |> 
}
