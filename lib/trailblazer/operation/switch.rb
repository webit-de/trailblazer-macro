class Trailblazer::Operation
  def self.Switch(condition:, key: :condition, id: "Switch(#{rand(100)})", &block)
    switch = Switch::Switched.new(key, block)

    condition_task = lambda do |(ctx, flow_options), **circuit_options|
      Switch::Condition.(ctx, circuit_options, condition: condition)

      return Trailblazer::Activity::Right, [ctx, flow_options]
    end

    activity = Module.new do
      extend Trailblazer::Activity::Railway()

      # pass because we cover the case we want to have a false/nil option
      pass task: condition_task, id: "extract_condition"
      # TODO: the id here it's wrong...I want to get the id from the actual switch option
      step task: switch, id: "switch_step"
    end

    {task: activity, id: id, outputs: activity.outputs}
  end

  module Switch
    class OptionNotFound < RuntimeError; end

    class Condition
      def self.call(ctx, circuit_options, condition:)
        Trailblazer::Option(condition).(ctx, ctx.to_hash, circuit_options)
      end
    end

    class Option
      include Trailblazer::Activity::DSL # to use Output, End and Track

      def initialize(condition)
        @condition = condition
        @count = 0
      end

      def option(expression, step, option_signal = {})
        return if @count == 1 # avoid to set @step and @signals twice so the order of the options is important
        # TODO: fix this, this would create issue with false/true and numbers
        return unless expression.match @condition

        @step = step
        @option_signal = option_signal
        @count += 1
      end

      def results
        [@step, @option_signal]
      end
    end

    class Switched
      def initialize(key, block)
        @key = key
        @block = block

        @outputs = {
          success: Trailblazer::Activity::Output(Railway::End::Success.new(semantic: :success), :success),
          failure: Trailblazer::Activity::Output(Railway::End::Failure.new(semantic: :failure), :failure),
          pass_fast: Trailblazer::Activity::Output(Railway::End::PassFast.new(semantic: :pass_fast), :pass_fast),
          fail_fast: Trailblazer::Activity::Output(Railway::End::FailFast.new(semantic: :fail_fast), :fail_fast)
        }

        @signal_to_output = {
          Trailblazer::Operation::Railway::End::Success => Trailblazer::Activity::Right,
          Trailblazer::Operation::Railway::End::Failure => Trailblazer::Activity::Left,
          # Railway.pass_fast! => outputs[:pass_fast].signal,
          # Railway.fail_fast! => outputs[:fail_fast].signal
        }
      end

      attr_reader :outputs

      def call((ctx, flow_options), **circuit_options)
        extract_step_and_option_signal(ctx[@key])

        original_signal, (ctx, flow_options) = @step[:task].([ctx, flow_options], **circuit_options)

        signal = @signal_to_output.fetch(original_signal.class, nil)

        # TODO: fix this!!!!!!
        if signal.nil?
          Trailblazer::Activity::DSL::End(original_signal.to_s.downcase.split("::").last.to_sym)

          signal = original_signal
        end

        return signal, [ctx, flow_options]
      end

      def extract_step_and_option_signal(condition)
        options = Option.new(condition)
        options.instance_exec(&@block)
        @step, @option_signal = options.results

        fail Switch::OptionNotFound if @step.nil?

        @step = {task: Trailblazer::Activity::TaskBuilder::Binary(@step)} if @step.is_a?(Symbol)
      end
    end
  end
end
