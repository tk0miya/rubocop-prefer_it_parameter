# rubocop-prefer_it_parameter

A RuboCop plugin that recommends using the `it` block parameter (Ruby 3.4+) instead of named block arguments in single-line blocks.

## Installation

Add the gem to your application's Gemfile. RuboCop loads it through `plugins:`, so it does not need to be required:

```ruby
group :development do
  gem "rubocop-prefer_it_parameter", require: false
end
```

Or install it directly:

```bash
gem install rubocop-prefer_it_parameter
```

Then add it to your `.rubocop.yml`:

```yaml
plugins:
  - rubocop-prefer_it_parameter
```

## Cops

### Style/PreferItParameter

Prefer the `it` block parameter over a named block argument in single-line blocks. Only blocks consisting of a single statement are converted. This cop supports autocorrection.

**Bad:**

```ruby
users.map { |user| user.name.upcase }
items.select { |item| item.active? && item.visible? }
```

**Good:**

```ruby
users.map { it.name.upcase }
items.select { it.active? && it.visible? }
```

A value omission is spelled out, since `{it:}` would call a method named `it`:

```ruby
# bad
items.map { |item| {item:} }

# good
items.map { {item: it} }
```

The autocorrection is marked unsafe — see [Safety](#safety).

#### Exceptions

A block is left alone when it:

- is multi-line — a named argument reads better there
- has two or more statements
- contains a nested block — only the innermost block is converted
- takes anything other than a single plain argument, including a trailing comma such as `|x,|` (which destructures the yielded value while `it` does not)
- rebinds its argument, by assignment or by pattern matching
- never references its argument (see `Lint/UnusedBlockArgument`)
- references a local variable named `it` from an enclosing scope, or assigns to `it`
- already names its argument `it` — dropping it would revive an `it` from an enclosing scope (`Style/ItAssignment` forbids the name instead)
- defines a callable or a method — `->(x) { }`, `lambda`, `proc`, `Proc.new`, `define_method`, `define_singleton_method` — since the parameter list is part of its API and `it` drops the parameter name
- is nested inside RSpec's custom matcher DSL (`RSpec::Matchers.define`) as `match`, `match_when_negated`, `match_unless_raises`, `chain`, `failure_message`, `failure_message_when_negated` or `description` — these blocks are turned into actual methods internally, where `it`'s implicit binding does not reliably survive (see below)
- matches a project-specific entry in `IgnoredBlockContexts` (see below)

The `Proc.new`/`lambda`/etc. and RSpec cases above are built into the cop and always checked — they cannot be turned off. `IgnoredBlockContexts` is how a project adds its own such cases on top of them.

#### `IgnoredBlockContexts`

A block can be unsafe to convert for reasons specific to how it's used, not just because of what method it's passed to — this is exactly why RSpec's matcher DSL and `Proc.new` are already built-in exceptions above. `IgnoredBlockContexts` lets a project name its *own* such cases the same way, each scoped to the call it's nested inside (or, for `Proc.new`-like cases, matched wherever it's called), so a generic method name doesn't suppress the check on unrelated code.

```ruby
# bad
RSpec::Matchers.define :be_valid_foo do
  match { it.is_a?(Foo) && it.valid? }
end

# good
RSpec::Matchers.define :be_valid_foo do
  match { |actual| actual.is_a?(Foo) && actual.valid? }
end
```

`IgnoredBlockContexts` is empty by default. The built-in cases above are not stored in this config option at all — they're checked independently — so setting `IgnoredBlockContexts` in your `.rubocop.yml` only *adds* entries; it can never disable a built-in case:

```yaml
Style/PreferItParameter:
  IgnoredBlockContexts:
    OurDsl.define_matcher:
      - our_custom_dsl_method
```

A block named this way is only ignored when it's nested inside the matching enclosing call — so `our_custom_dsl_method { |x| x.foo }` written anywhere else is unaffected and still converted, even though the method name is the same. This is what keeps a generic name from silently suppressing the check on unrelated code.

An enclosing call written without a receiver (`define_matcher:` instead of `OurDsl.define_matcher:`) only matches a bare call with no receiver at all. Write `*.define_matcher:` to match regardless of receiver instead — the same way `lambda` or `define_method` are matched in the exceptions list above. A value of `nil` (an entry with nothing under it) means the call itself is unsafe wherever it appears, with no nesting required — this is how the built-in `Proc.new` case works internally:

```yaml
Style/PreferItParameter:
  IgnoredBlockContexts:
    "*.our_dsl_method":  # any receiver, no nesting required
    OurDsl.define_matcher:  # this exact receiver, blocks nested inside it
      - our_custom_dsl_method
```

## Related cops

### `Style/ItBlockParameter` (RuboCop core)

It ships as `Enabled: pending`, so it needs `NewCops: enable` or an explicit `Enabled: true`. Once enabled, the two cops do not conflict — they cover different cells of the same grid:

| | `Style/PreferItParameter` (this gem) | `Style/ItBlockParameter` (core, `allow_single_line`) |
|---|---|---|
| single-line block with a named argument | offense | — |
| single-line block using `_1` | — | offense |
| multi-line block using `_1` | — | offense |
| multi-line block using `it` | — | offense |
| multi-line block with a named argument | — | — |

Enabling both enforces "use `it` for single-line blocks, use a named argument for multi-line blocks" consistently.

Do not set core's cop to `EnforcedStyle: always` — it then checks named block arguments as well, and the two autocorrections collide on the same block.

### `Style/ItAssignment` (RuboCop core) — recommended

```yaml
Style/ItAssignment:
  Enabled: true
```

`Style/ItAssignment` forbids naming a local variable or parameter `it`, which `Style/PreferItParameter` cannot fully guard against on its own — see [Safety](#safety).

## Safety

The autocorrection is marked unsafe (`SafeAutoCorrect: false`), so `rubocop -a` reports the offenses without changing anything and `rubocop -A` is needed to apply them. `it` is not equivalent to a named argument in every respect:

- A local variable or parameter named `it` takes precedence over the block parameter. The cop skips a block that references such a variable, but it cannot detect one that the block never references — there the autocorrection silently changes what the block sees. Enabling `Style/ItAssignment` is therefore a prerequisite.
- `Proc#parameters` loses the argument name: `[[:opt, :x]]` becomes `[[:opt]]`. Blocks that define a callable or a method are excluded for this reason, but a block captured with `&block` and introspected elsewhere is still affected.
- `binding.local_variable_get(:x)` inside the block stops working.
- A block can be unsafe to convert for reasons specific to its own context — e.g. a library that turns it into an actual method internally may stop passing it an argument at all. RSpec's custom matcher DSL is built in for this reason (see [Exceptions](#exceptions)); [`IgnoredBlockContexts`](#ignoredblockcontexts) lets a project name the same kind of case for a library this cop doesn't know about.

## Requirements

- Ruby >= 3.4
- RuboCop >= 1.75.0

The cop only inspects projects whose `TargetRubyVersion` is 3.4 or higher, since that is when `it` was introduced.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the whole check suite (RuboCop, RSpec, Steep and RBS validation), or `bundle exec rake spec` for the tests alone. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Releasing

Bump `VERSION` in `lib/rubocop/prefer_it_parameter/version.rb`, add an entry to [CHANGELOG.md](CHANGELOG.md), and merge that into `main`. The [release workflow](.github/workflows/release.yml) picks up the change to `version.rb`, tags the version, and pushes the gem to [rubygems.org](https://rubygems.org) through trusted publishing. It can also be started by hand from the Actions tab.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tk0miya/rubocop-prefer_it_parameter. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/tk0miya/rubocop-prefer_it_parameter/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the rubocop-prefer_it_parameter project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/tk0miya/rubocop-prefer_it_parameter/blob/main/CODE_OF_CONDUCT.md).
