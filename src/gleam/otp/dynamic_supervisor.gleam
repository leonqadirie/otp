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
  /// Automic shutdown is disabled. This is the default setting.
  ///
  /// With auto_shutdown set to never, child specs with the significant flag
  /// set to true are considered invalid and will be rejected.
  Never
  /// The supervisor will shut itself down when any significant child
  /// terminates, that is, when a transient significant child terminates
  /// normally or when a temporary significant child terminates normally or
  /// abnormally.
  AnySignificant
  /// The supervisor will shut itself down when all significant children have
  /// terminated, that is, when the last active significant child terminates.
  /// The same rules as for any_significant apply.
  AllSignificant
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

pub opaque type ChildBuilder {
  ChildBuilder(fields: Int)
}
