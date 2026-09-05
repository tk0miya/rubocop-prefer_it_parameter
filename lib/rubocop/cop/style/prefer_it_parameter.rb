# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Prefer the `it` block parameter over a named block argument in single-line blocks.
      #
      # Only blocks consisting of a single statement are converted. This cop complements
      # `Style/ItBlockParameter` in RuboCop core, which converts `_1` to `it` but in its
      # default style does not check named block arguments.
      #
      # @safety
      #   The autocorrection is unsafe because a local variable named `it` that the
      #   block does not reference cannot be detected, and replacing it would silently
      #   change what the block sees. Enabling `Style/ItAssignment` rules such names
      #   out. Additionally, `it` drops the argument name from `Proc#parameters`
      #   (`[[:opt, :x]]` becomes `[[:opt]]`) and breaks
      #   `binding.local_variable_get(:x)` inside the block. A block captured with
      #   `&block` and introspected elsewhere is still affected even when none of
      #   the below applies.
      #
      #   Some blocks are unsafe to convert for reasons this cop cannot see from the
      #   AST alone — `->(x) { }`, `lambda`, `proc`, `Proc.new`, `define_method` and
      #   `define_singleton_method` all define a callable or a method, where the
      #   parameter list is part of its API and `it` drops the parameter name; RSpec's
      #   custom matcher DSL turns `match`, `chain` and similar blocks into actual
      #   methods internally, where `it`'s implicit binding does not reliably survive.
      #   These are all built in and cannot be turned off. `IgnoredBlockContexts` lets
      #   a project add its own cases the same way, scoped to where they're nested so
      #   a generic method name doesn't suppress the check on unrelated code.
      #
      # @example
      #   # bad
      #   users.map { |user| user.name.upcase }
      #   items.select { |item| item.active? && item.visible? }
      #
      #   # good
      #   users.map { it.name.upcase }
      #   items.select { it.active? && it.visible? }
      #
      #   # good - multi-line block
      #   users.each do |user|
      #     user.activate!
      #     notify(user)
      #   end
      #
      #   # good - the block consists of two statements
      #   items.each { |item| validate(item); save(item) }
      #
      #   # good - only the innermost block may use `it`
      #   matrix.map { |row| row.map { it * 2 } }
      #
      #   # good - `|x,|` destructures the yielded value, unlike `it`
      #   pairs.each { |pair,| puts pair }
      #
      #   # good - a callable's parameter list is part of its API
      #   ->(x) { puts x }
      #   define_method(:m) { |x| x + 1 }
      #
      #   # good - RSpec turns this block into a method internally, where `it` cannot be trusted
      #   RSpec::Matchers.define :be_valid_foo do
      #     match { |actual| actual.valid? }
      #   end
      #
      #   # bad
      #   items.map { |item| {item:} }
      #
      #   # good - the value is spelled out, since `{it:}` would call a method named `it`
      #   items.map { {item: it} }
      #
      class PreferItParameter < Base
        extend AutoCorrector
        extend TargetRubyVersion
        include RangeHelp

        minimum_target_ruby_version 3.4

        MSG = "Use the `it` block parameter instead of the named block argument `%<name>s`."

        INNER_BLOCK_TYPES = %i[block numblock itblock].freeze #: Array[Symbol]

        # Maps a call to the method names that are unsafe when nested inside it, in
        # the same format as the `IgnoredBlockContexts` config option (see
        # `matches_context?` for the exact matching rules). A `nil` value means the
        # call itself is unsafe, wherever it appears, with no nesting required —
        # `lambda`/`proc`/`define_method`/`define_singleton_method` match regardless
        # of receiver (`*.`), `Proc.new` requires that exact receiver. These are core
        # Ruby behavior and RSpec's widely-used matcher DSL, so unlike
        # `IgnoredBlockContexts` they're built in and cannot be turned off.
        BUILTIN_IGNORED_BLOCK_CONTEXTS = {
          "*.lambda" => nil,
          "*.proc" => nil,
          "*.define_method" => nil,
          "*.define_singleton_method" => nil,
          "Proc.new" => nil,
          "RSpec::Matchers.define" => %i[
            match match_when_negated match_unless_raises chain
            failure_message failure_message_when_negated description
          ]
        }.freeze #: Hash[String, Array[Symbol]?]

        # @rbs node: RuboCop::AST::BlockNode
        def on_block(node) #: void
          body = node.body
          return unless body

          name = convertible_argument_name(node, body)
          return unless name

          references = lvar_references(body, name)
          return if references.empty?

          register_offense(node, name, references)
        end

        private

        # @rbs node: RuboCop::AST::BlockNode
        # @rbs body: RuboCop::AST::Node
        def convertible_argument_name(node, body) #: Symbol?
          return unless node.single_line?
          return if ignored?(node)

          name = sole_argument_name(node)
          return unless name
          return unless convertible_body?(body, name)
          return if shadows_it?(body)

          name
        end

        # `it` would not mean what the block expects when a local variable named `it`
        # is already in scope, or when the body assigns to `it` — assigning turns `it`
        # into a plain local variable and disables the implicit block parameter.
        #
        # @rbs body: RuboCop::AST::Node
        def shadows_it?(body) #: bool
          lvar_references(body, :it).any? || reassigned?(body, :it)
        end

        # A block can be unsafe to convert for reasons specific to how it's used, not
        # just because of what method it's passed to — see `BUILTIN_IGNORED_BLOCK_CONTEXTS`
        # for the built-in cases and `matches_context?` for what a context means.
        # `IgnoredBlockContexts` lets a project add its own cases the same way; it is
        # checked separately from, and in addition to, the built-in ones, so a project
        # can never accidentally disable those by overriding this config option.
        #
        # @rbs node: RuboCop::AST::BlockNode
        def ignored?(node) #: bool
          ignored_in?(node, BUILTIN_IGNORED_BLOCK_CONTEXTS) || ignored_in?(node, ignored_block_contexts)
        end

        # @rbs node: RuboCop::AST::BlockNode
        # @rbs contexts: Hash[String, Array[Symbol]?]
        def ignored_in?(node, contexts) #: bool
          contexts.any? { |context, method_names| matches_context?(node, context, method_names) }
        end

        # @rbs @ignored_block_contexts: Hash[String, Array[Symbol]?]

        def ignored_block_contexts #: Hash[String, Array[Symbol]?]
          default = {} #: Hash[String, Array[String]?]
          @ignored_block_contexts ||= cop_config.fetch("IgnoredBlockContexts", default).transform_values do |names|
            names&.map(&:to_sym)
          end
        end

        # A `nil` (or empty) `method_names` means `context` describes the node's own
        # call, checked with no nesting required — this is how `Proc.new` and the
        # receiver-blind `*.lambda`-style entries work. Otherwise, `context` names an
        # enclosing call the node must be nested inside, and `method_names` are the
        # names that are unsafe within it — this is how RSpec's matcher DSL works.
        #
        # @rbs node: RuboCop::AST::BlockNode
        # @rbs context: String
        # @rbs method_names: Array[Symbol]?
        def matches_context?(node, context, method_names) #: bool
          if method_names.nil? || method_names.empty?
            receiver_source, method_name = parse_context(context)
            context_call?(node.send_node, receiver_source, method_name)
          else
            method_names.include?(node.method_name) && nested_in_context?(node, context)
          end
        end

        # `numblock` and `itblock` (a `_1` or `it` block) are included since
        # rubocop-ast maps both to `BlockNode`, so `#send_node` works the same as for
        # a plain `block`.
        #
        # @rbs node: RuboCop::AST::BlockNode
        # @rbs context: String
        def nested_in_context?(node, context) #: bool
          receiver_source, method_name = parse_context(context)
          node.each_ancestor(*INNER_BLOCK_TYPES).any? do |ancestor|
            block_ancestor = ancestor #: RuboCop::AST::BlockNode
            context_call?(block_ancestor.send_node, receiver_source, method_name)
          end
        end

        # @rbs context: String
        def parse_context(context) #: [String, String]
          receiver_source, _dot, method_name = context.rpartition(".")
          [receiver_source, method_name]
        end

        # `receiver_source` of `"*"` matches any receiver, or none. An empty
        # `receiver_source` (`context` had no `.`) requires no receiver at all.
        # Otherwise the receiver's source must match exactly, modulo a leading `::`
        # on either side — `::Proc` is not receiver-less, its source is `"::Proc"`
        # (a `cbase`-prefixed const), so this is what lets `Proc.new` also match
        # `::Proc.new`.
        #
        # @rbs send_node: RuboCop::AST::SendNode
        # @rbs receiver_source: String
        # @rbs method_name: String
        def context_call?(send_node, receiver_source, method_name) #: bool
          return false unless send_node.method?(method_name.to_sym)
          return true if receiver_source == "*"
          return send_node.receiver.nil? if receiver_source.empty?

          actual_receiver_source = send_node.receiver&.source
          return false unless actual_receiver_source

          actual_receiver_source.delete_prefix("::") == receiver_source.delete_prefix("::")
        end

        # @rbs node: RuboCop::AST::BlockNode
        def sole_argument_name(node) #: Symbol?
          return unless node.argument_list.one?

          argument = node.first_argument
          # Rules out optarg, restarg, kwarg, blockarg, shadowarg and mlhs at once.
          return unless argument&.arg_type?
          # `|x,|` is indistinguishable from `|x|` in the AST even though it
          # destructures the yielded value, so the source has to be checked.
          return if node.arguments.source&.include?(",")

          plain_argument = argument #: RuboCop::AST::ArgNode
          plain_argument.name
        end

        # @rbs body: RuboCop::AST::Node
        # @rbs name: Symbol
        def convertible_body?(body, name) #: bool
          single_statement?(body) && !contains_block?(body) && !reassigned?(body, name)
        end

        # `begin` (parentheses) and `kwbegin` (`begin ... end`) both wrap a sequence of
        # statements as well as a single expression, so the number of children is what
        # tells the two apart.
        #
        # @rbs body: RuboCop::AST::Node
        def single_statement?(body) #: bool
          return body.each_child_node.one? if body.type?(:begin, :kwbegin)

          true
        end

        # `it` is a syntax error inside a block that has an ordinary parameter, and
        # silently shadows the outer one inside a parameterless block, so only the
        # innermost block is converted.
        #
        # @rbs body: RuboCop::AST::Node
        def contains_block?(body) #: bool
          body.each_node(*INNER_BLOCK_TYPES).any?
        end

        # A block that rebinds the name cannot be converted: the value `it` refers to
        # would no longer be the one the block was yielded. `match_var` covers pattern
        # matching (`1 in x`), which rebinds just like an assignment.
        #
        # @rbs body: RuboCop::AST::Node
        # @rbs name: Symbol
        def reassigned?(body, name) #: bool
          body.each_node(:lvasgn, :match_var).any? do |node|
            node.to_a.first == name
          end
        end

        # Returns the enclosing pair when the reference is a value omission (`{x:}`,
        # `foo(x:)`). Such a reference shares its source range with the label, so the
        # value has to be written after the pair rather than replaced.
        #
        # @rbs reference: RuboCop::AST::Node
        def omitted_value_pair(reference) #: RuboCop::AST::PairNode?
          parent = reference.parent
          return unless parent&.pair_type?

          pair = parent #: RuboCop::AST::PairNode
          pair if pair.value_omission?
        end

        # @rbs body: RuboCop::AST::Node
        # @rbs name: Symbol
        def lvar_references(body, name) #: Array[RuboCop::AST::Node]
          body.each_node(:lvar).select do |node|
            variable = node #: RuboCop::AST::VarNode
            variable.name == name
          end
        end

        # @rbs node: RuboCop::AST::BlockNode
        # @rbs name: Symbol
        # @rbs references: Array[RuboCop::AST::Node]
        def register_offense(node, name, references) #: void
          add_offense(node.arguments, message: format(MSG, name:)) do |corrector|
            references.each do |reference|
              replace_reference(corrector, reference)
            end
            corrector.remove(arguments_removal_range(node))
          end
        end

        # @rbs corrector: RuboCop::Cop::Corrector
        # @rbs reference: RuboCop::AST::Node
        def replace_reference(corrector, reference) #: void
          pair = omitted_value_pair(reference)
          if pair
            corrector.insert_after(pair.source_range, " it")
          else
            corrector.replace(reference.source_range, "it")
          end
        end

        # @rbs node: RuboCop::AST::BlockNode
        def arguments_removal_range(node) #: Parser::Source::Range
          range_with_surrounding_space(node.arguments.source_range, side: :right, newlines: false)
        end
      end
    end
  end
end
