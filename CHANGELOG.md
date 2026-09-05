## [Unreleased]

- `Style/PreferItParameter`: recognize RSpec's custom matcher DSL (`RSpec::Matchers.define`)
  as a built-in exception, alongside `lambda`/`proc`/`Proc.new`/`define_method`/
  `define_singleton_method`; these are always checked and cannot be disabled.
- `Style/PreferItParameter`: add the `IgnoredBlockContexts` config option, so a project
  can name its own such unsafe blocks on top of the built-ins above. As part of this,
  the built-in `Proc.new` check now matches by exact receiver source text rather than
  resolved constant name, so a `Proc` reached through another namespace is no longer
  recognized.

## [1.0.0] - 2026-08-05

Initial release.

- `Style/PreferItParameter`: recommends the `it` block parameter (Ruby 3.4+) over a named
  block argument in single-line blocks. Autocorrection is available but unsafe, so
  `rubocop -A` is required to apply it. Only projects with `TargetRubyVersion` 3.4 or
  higher are inspected; see the README for the cases the cop skips.
