# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Style::PreferItParameter, :config do
  # The `it` block parameter requires Ruby 3.4, while RuboCop defaults to 2.7.
  let(:ruby_version) { 3.4 }

  context "with single-line block" do
    context "with a method call" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          users.map { |user| user.name }
                      ^^^^^^ Use the `it` block parameter instead of the named block argument `user`.
        RUBY

        expect_correction(<<~RUBY)
          users.map { it.name }
        RUBY
      end
    end

    context "when the body is the argument itself" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          users.map { |x| x }
                      ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          users.map { it }
        RUBY
      end
    end

    context "without spaces around braces" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          users.map{|user| user.name}
                    ^^^^^^ Use the `it` block parameter instead of the named block argument `user`.
        RUBY

        expect_correction(<<~RUBY)
          users.map{it.name}
        RUBY
      end
    end

    context "with multiple references" do
      it "registers an offense and corrects every reference" do
        expect_offense(<<~'RUBY')
          users.map { |u| "#{u.first_name} #{u.last_name}" }
                      ^^^ Use the `it` block parameter instead of the named block argument `u`.
        RUBY

        expect_correction(<<~'RUBY')
          users.map { "#{it.first_name} #{it.last_name}" }
        RUBY
      end
    end

    context "with a modifier if" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          list.each { |x| puts x if x }
                      ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          list.each { puts it if it }
        RUBY
      end
    end

    context "with a parenthesized single statement" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          a.map { |x| (x + 1) }
                  ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          a.map { (it + 1) }
        RUBY
      end
    end

    context "with a single-line do...end block" do
      it "registers an offense and corrects without breaking the block syntax" do
        expect_offense(<<~RUBY)
          a.each do |x| puts x end
                    ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          a.each do puts it end
        RUBY
      end
    end

    context "with an or-assignment to a receiver" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          a.each { |x| @m[x] ||= x.to_s }
                   ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          a.each { @m[it] ||= it.to_s }
        RUBY
      end
    end

    context "with a heredoc" do
      # The heredoc body sits on later lines, but the block itself is single-line.
      it "registers an offense and corrects the reference inside the heredoc" do
        expect_offense(<<~'RUBY')
          a.each { |x| puts(<<~T) }
                   ^^^ Use the `it` block parameter instead of the named block argument `x`.
            #{x}
          T
        RUBY

        expect_correction(<<~'RUBY')
          a.each { puts(<<~T) }
            #{it}
          T
        RUBY
      end
    end

    context "with chained blocks on the same line" do
      it "registers an offense for each block and corrects" do
        expect_offense(<<~RUBY)
          a.map { |x| x + 1 }.select { |y| y > 2 }
                  ^^^ Use the `it` block parameter instead of the named block argument `x`.
                                       ^^^ Use the `it` block parameter instead of the named block argument `y`.
        RUBY

        expect_correction(<<~RUBY)
          a.map { it + 1 }.select { it > 2 }
        RUBY
      end
    end

    context "when the block defines a callable" do
      context "with the `lambda` method" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            lambda { |x| x.foo }
          RUBY
        end
      end

      context "with the `lambda` method on an explicit receiver" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            Kernel.lambda { |x| x.foo }
          RUBY
        end
      end

      context "with the `proc` method" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            proc { |x| x.foo }
          RUBY
        end
      end

      context "with `define_method`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            define_method(:m) { |x| x + 1 }
          RUBY
        end
      end

      context "with `define_singleton_method`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            define_singleton_method(:m) { |x| x + 1 }
          RUBY
        end
      end

      context "with RSpec's custom matcher DSL" do
        # RSpec's `RSpec::Matchers.define` turns `match`/`chain`/etc. blocks into
        # actual methods internally, where `it`'s implicit binding does not
        # reliably survive. This is built in and always checked, regardless of
        # `IgnoredBlockContexts` — a project can add its own such cases, but
        # cannot remove this one.
        context "when `match` is nested in `RSpec::Matchers.define`" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              RSpec::Matchers.define :be_valid_foo do
                match { |actual| actual.is_a?(Foo) && actual.valid? }
              end
            RUBY
          end
        end

        context "when `chain` is nested in `RSpec::Matchers.define`" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              RSpec::Matchers.define :be_valid_foo do
                chain(:with) { |message| @message = message }
              end
            RUBY
          end
        end

        context "when `match` is nested nowhere" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              match { |actual| actual.is_a?(Foo) && actual.valid? }
                      ^^^^^^^^ Use the `it` block parameter instead of the named block argument `actual`.
            RUBY

            expect_correction(<<~RUBY)
              match { it.is_a?(Foo) && it.valid? }
            RUBY
          end
        end

        context "when a `match` method unrelated to RSpec shares the name" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              class CustomRouter
                match { |request| request.path == "/" }
                        ^^^^^^^^^ Use the `it` block parameter instead of the named block argument `request`.
              end
            RUBY

            expect_correction(<<~RUBY)
              class CustomRouter
                match { it.path == "/" }
              end
            RUBY
          end
        end

        context "when the enclosing receiver does not match" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              SomeOtherThing.define do
                match { |actual| actual.valid? }
                        ^^^^^^^^ Use the `it` block parameter instead of the named block argument `actual`.
              end
            RUBY

            expect_correction(<<~RUBY)
              SomeOtherThing.define do
                match { it.valid? }
              end
            RUBY
          end
        end

        context "when nested in `RSpec::Matchers.define` but the method name is not one of the built-in ones" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              RSpec::Matchers.define :be_valid_foo do
                some_other_method { |actual| actual.valid? }
                                    ^^^^^^^^ Use the `it` block parameter instead of the named block argument `actual`.
              end
            RUBY

            expect_correction(<<~RUBY)
              RSpec::Matchers.define :be_valid_foo do
                some_other_method { it.valid? }
              end
            RUBY
          end
        end

        context "when `IgnoredBlockContexts` is explicitly cleared" do
          let(:cop_config) { { "IgnoredBlockContexts" => {} } }

          it "still does not register an offense" do
            expect_no_offenses(<<~RUBY)
              RSpec::Matchers.define :be_valid_foo do
                match { |actual| actual.valid? }
              end
            RUBY
          end
        end
      end
    end

    context "with `IgnoredBlockContexts`" do
      # `IgnoredBlockContexts` lets a project name its own blocks that are unsafe
      # to convert, on top of the built-in cases (RSpec's matcher DSL, `Proc.new`,
      # etc. — see "when the block defines a callable").
      context "with a context that has no receiver" do
        let(:cop_config) { { "IgnoredBlockContexts" => { "define_matcher" => %w[our_custom_dsl_method] } } }

        context "when nested inside the bare defining call" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              define_matcher do
                our_custom_dsl_method { |x| x.foo }
              end
            RUBY
          end
        end

        context "when outside the defining call" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              our_custom_dsl_method { |x| x.foo }
                                      ^^^ Use the `it` block parameter instead of the named block argument `x`.
            RUBY

            expect_correction(<<~RUBY)
              our_custom_dsl_method { it.foo }
            RUBY
          end
        end

        context "when the defining call has a receiver" do
          it "registers an offense and corrects" do
            expect_offense(<<~RUBY)
              OurDsl.define_matcher do
                our_custom_dsl_method { |x| x.foo }
                                        ^^^ Use the `it` block parameter instead of the named block argument `x`.
              end
            RUBY

            expect_correction(<<~RUBY)
              OurDsl.define_matcher do
                our_custom_dsl_method { it.foo }
              end
            RUBY
          end
        end

        context "when the defining call itself uses `it`" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              define_matcher do
                our_custom_dsl_method { |x| x.foo }
                it.finish
              end
            RUBY
          end
        end
      end

      context "with a receiver-qualified context" do
        let(:cop_config) { { "IgnoredBlockContexts" => { "OurDsl.define_matcher" => %w[our_custom_dsl_method] } } }

        it "does not register an offense when nested inside the matching defining call" do
          expect_no_offenses(<<~RUBY)
            OurDsl.define_matcher do
              our_custom_dsl_method { |x| x.foo }
            end
          RUBY
        end
      end

      context "with a receiver-blind (`*.`) flat context" do
        let(:cop_config) { { "IgnoredBlockContexts" => { "*.our_flat_method" => nil } } }

        context "when called with no receiver" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              our_flat_method { |x| x.foo }
            RUBY
          end
        end

        context "when called on any receiver" do
          it "does not register an offense" do
            expect_no_offenses(<<~RUBY)
              OurDsl.our_flat_method { |x| x.foo }
            RUBY
          end
        end
      end
    end

    context "with `new`" do
      context "when the receiver is `Proc`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            Proc.new { |x| x.foo }
          RUBY
        end
      end

      context "when the receiver is `::Proc`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            ::Proc.new { |x| x.foo }
          RUBY
        end
      end

      context "when the receiver is another class" do
        it "registers an offense and corrects" do
          expect_offense(<<~RUBY)
            Thread.new { |x| puts x }
                         ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            Thread.new { puts it }
          RUBY
        end
      end

      context "when the receiver is `Proc` reached through another namespace" do
        # Only a bare `Proc`/`::Proc` receiver is recognized, by source text —
        # not whatever constant a namespaced reference like this would actually
        # resolve to at runtime.
        it "registers an offense and corrects" do
          expect_offense(<<~RUBY)
            Foo::Bar::Proc.new { |x| x.foo }
                                 ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            Foo::Bar::Proc.new { it.foo }
          RUBY
        end
      end
    end

    context "with nested blocks" do
      context "when the nested block takes a named argument" do
        it "registers an offense on the innermost block only and corrects" do
          expect_offense(<<~RUBY)
            matrix.map { |row| row.map { |cell| cell * 2 } }
                                         ^^^^^^ Use the `it` block parameter instead of the named block argument `cell`.
          RUBY

          expect_correction(<<~RUBY)
            matrix.map { |row| row.map { it * 2 } }
          RUBY
        end
      end

      context "when the nested block uses numbered parameters" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| list2.each { _1 + x } }
          RUBY
        end
      end

      context "when the nested block uses `it`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| l2.each { puts it } }
          RUBY
        end
      end
    end

    context "with two statements" do
      context "with two method calls" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            h.each { |k| puts k; puts k }
          RUBY
        end
      end

      context "with a modifier if and another statement" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            a.each { |x| next if x; puts x }
          RUBY
        end
      end

      context "with an assignment and another statement" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| x = 1; puts x }
          RUBY
        end
      end

      context "with a begin block" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            e.map { |x| begin; puts x; puts x; end }
          RUBY
        end
      end
    end

    context "with an empty body" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          items.each { |item| }
        RUBY
      end
    end

    context "without a single plain argument" do
      context "without arguments" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            3.times { puts "hello" }
          RUBY
        end
      end

      context "with two arguments" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            hash.each { |key, value| key }
          RUBY
        end
      end

      context "with destructuring arguments" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            pairs.map { |(key, value)| key }
          RUBY
        end
      end

      context "with a single-element destructuring argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            pairs.map { |(key)| key }
          RUBY
        end
      end

      context "with a splat argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |*args| args.first }
          RUBY
        end
      end

      context "with a block argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |&block| block.call }
          RUBY
        end
      end

      context "with a shadow variable" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |item; temp| temp = item }
          RUBY
        end
      end

      context "with an optional argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |item = 1| item }
          RUBY
        end
      end

      context "with a keyword argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |key:| key }
          RUBY
        end
      end

      context "with a keyword splat argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            items.each { |**opts| opts }
          RUBY
        end
      end

      context "with a trailing comma" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            data.each { |x,| puts x }
          RUBY
        end
      end

      context "with a trailing comma surrounded by spaces" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            data.each { |x , | puts x }
          RUBY
        end
      end
    end

    context "when the argument is rebound" do
      context "with an assignment" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| x = x + 1 }
          RUBY
        end
      end

      context "with an operator assignment" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| x += 1 }
          RUBY
        end
      end
    end

    context "with pattern matching" do
      context "when the pattern rebinds the argument" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            a.each { |x| puts x if 1 in x }
          RUBY
        end
      end

      context "when the pattern pins the argument" do
        it "registers an offense and corrects" do
          expect_offense(<<~RUBY)
            ids.select { |id| record in {id: ^id} }
                         ^^^^ Use the `it` block parameter instead of the named block argument `id`.
          RUBY

          expect_correction(<<~RUBY)
            ids.select { record in {id: ^it} }
          RUBY
        end
      end
    end

    context "when another variable is assigned" do
      it "registers an offense and corrects" do
        expect_offense(<<~RUBY)
          list.each { |x| y = x }
                      ^^^ Use the `it` block parameter instead of the named block argument `x`.
        RUBY

        expect_correction(<<~RUBY)
          list.each { y = it }
        RUBY
      end
    end

    context "when the argument is used as an omitted value" do
      context "with a hash" do
        it "registers an offense and spells the value out" do
          expect_offense(<<~RUBY)
            a.map { |x| {x:} }
                    ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            a.map { {x: it} }
          RUBY
        end
      end

      context "with an omitted value alongside a plain reference" do
        it "registers an offense and corrects both" do
          expect_offense(<<~RUBY)
            a.map { |x| foo(x:, y: x) }
                    ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            a.map { foo(x: it, y: it) }
          RUBY
        end
      end
    end

    context "when the argument is unused" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          items.each { |unused| puts 1 }
        RUBY
      end
    end

    context "when `it` already means something else" do
      context "when the block references a local variable named `it`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            it = 5
            list.each { |x| puts x + it }
          RUBY
        end
      end

      context "when the block assigns to `it`" do
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |x| it = x.to_s }
          RUBY
        end
      end

      context "when the argument is named `it`" do
        # The body's `it` always binds to the argument, so an `it` in an enclosing
        # scope cannot be detected from the body at all.
        it "does not register an offense" do
          expect_no_offenses(<<~RUBY)
            list.each { |it| puts it }
          RUBY
        end
      end

      # An `it` with no receiver and no arguments cannot appear here — Ruby rejects it
      # while the block still has an ordinary parameter — so only forms that are
      # unambiguously method calls coexist, and they stay method calls afterwards.
      context "when the body calls a method named `it` with parentheses" do
        it "registers an offense and corrects" do
          expect_offense(<<~RUBY)
            a.map { |x| [it(), x] }
                    ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            a.map { [it(), it] }
          RUBY
        end
      end

      context "when an unreferenced local variable named `it` is in scope" do
        # A known limitation, documented under `@safety`: the cop cannot tell that
        # `it` already means 5 here, so the correction changes what the block sees.
        it "registers an offense" do
          expect_offense(<<~RUBY)
            it = 5
            list.each { |x| puts x }
                        ^^^ Use the `it` block parameter instead of the named block argument `x`.
          RUBY

          expect_correction(<<~RUBY)
            it = 5
            list.each { puts it }
          RUBY
        end
      end
    end

    context "with numbered parameters already" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          users.map { _1.name }
        RUBY
      end
    end

    context "with the `it` parameter already" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          users.map { it.name }
        RUBY
      end
    end
  end

  context "with multi-line block" do
    context "with do...end" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          users.map do |user|
            user.name
          end
        RUBY
      end
    end

    context "with braces" do
      it "does not register an offense" do
        expect_no_offenses(<<~RUBY)
          users.map { |user|
            user.name
          }
        RUBY
      end
    end
  end

  context "when TargetRubyVersion is 3.3" do
    let(:ruby_version) { 3.3 }

    it "does not register an offense" do
      expect_no_offenses(<<~RUBY)
        users.map { |user| user.name }
      RUBY
    end
  end
end
