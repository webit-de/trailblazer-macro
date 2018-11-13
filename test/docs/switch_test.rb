require "test_helper"
require "ostruct"

module DocsSwitchTest
  class ChargeStripe < Trailblazer::Operation
    step :charge

    def charge(_ctx, model:, **)
      model.charge_id = 1
      model.save
    end
  end

  class NoCustomSignals < MiniTest::Spec
    class ChargeSwitch < Trailblazer::Operation
      step :set_model
      step Switch(condition: :set_condition) {
        option "stripe",    Trailblazer::Operation::Nested(ChargeStripe)
        option "braintree", :braintree
        option /./,         :unsupported
      }
      step :invoice
      fail :error

      def set_model(ctx, integration:, save: true, **)
        ctx[:model] = OpenStruct.new(bill_integration: integration, save: save)
      end

      def set_condition(ctx, model:, **)
        ctx[:condition] = model.bill_integration
      end

      def braintree(_ctx, model:, **)
        model.charge_id = 2
        model.save
      end

      def invoice(ctx, model:, **)
        ctx[:invoice] = OpenStruct.new(type: model.bill_integration, charge_id: model.charge_id)
      end

      def unsupported(ctx, *)
        ctx[:error] = "Unsupported bill integration"
        false
      end

      def error(ctx, *)
        ctx[:error] ||= "Something wrong happened"
      end
    end

    it "when integration is stripe" do
      result = ChargeSwitch.trace(integration: "stripe")
      pp result.wtf?

      result.success?.must_equal true
      result[:model].charge_id.must_equal 1
      result[:invoice].type.must_equal "stripe"
      result[:invoice].charge_id.must_equal 1
    end

    it "when integration is stripe but save is failing" do
      result = ChargeSwitch.trace(integration: "stripe", save: false)
      pp result.wtf?

      result.failure?.must_equal true
      result[:model].charge_id.must_equal 1
      result[:error].must_equal "Something wrong happened"
    end

    it "when integration is braintree" do
      result = ChargeSwitch.trace(integration: "braintree")
      pp result.wtf?

      result.success?.must_equal true
      result[:model].charge_id.must_equal 2
      result[:invoice].type.must_equal "braintree"
      result[:invoice].charge_id.must_equal 2
    end

    it "when integration is braintree but save is failing" do
      result = ChargeSwitch.trace(integration: "braintree", save: false)
      pp result.wtf?

      result.failure?.must_equal true
      result[:model].charge_id.must_equal 2
      result[:error].must_equal "Something wrong happened"
    end

    it "when integration is not supported" do
      result = ChargeSwitch.trace(integration: "smoko")
      pp result.wtf?

      result[:error].must_equal "Unsupported bill integration"
    end
  end

  class WithCustomSignals < MiniTest::Spec
    class ChargeSwitch < Trailblazer::Operation
      class Braintree < Trailblazer::Activity::Signal; end

      step :set_model
      step Switch(condition: :set_condition) {
        option "stripe",    Trailblazer::Operation::Nested(ChargeStripe)
        option "braintree", :braintree, Output(Braintree, :success) => Track(:braintree)
        option /./,         :unsupported
      }
      step :stripe_invoice
      step :braintree_invoice, magnetic_to: [:braintree], Output(:success) => End(:success_braintree),
                                                          Output(:failure) => End(:failure_braintree)
      fail :error

      def set_model(ctx, integration:, save: true, **)
        ctx[:model] = OpenStruct.new(bill_integration: integration, save: save)
      end

      def set_condition(ctx, model:, **)
        ctx[:condition] = model.bill_integration
      end

      def stripe_invoice(ctx, model:, **)
        ctx[:invoice] = OpenStruct.new(type: "stripe", charge_id: model.charge_id)
      end

      def braintree(_ctx, model:, **)
        model.charge_id = 2
        model.save ? Braintree : false
      end

      def braintree_invoice(ctx, model:, **)
        ctx[:invoice] = OpenStruct.new(type: "braintree", charge_id: model.charge_id)
      end

      def unsupported(ctx, *)
        ctx[:error] = "Unsupported bill integration"
        false
      end

      def error(ctx, *)
        ctx[:error] ||= "Something wrong happened"
      end
    end

    # TODO: add signals tests
    it "when integration is stripe" do
      result = ChargeSwitch.trace(integration: "stripe")
      pp result.wtf?

      result.success?.must_equal true
      result[:model].charge_id.must_equal 1
      result[:invoice].type.must_equal "stripe"
      result[:invoice].charge_id.must_equal 1
    end

    it "when integration is stripe but save is failing" do
      result = ChargeSwitch.trace(integration: "stripe", save: false)
      pp result.wtf?

      result.failure?.must_equal true
      result[:model].charge_id.must_equal 1
      result[:error].must_equal "Something wrong happened"
    end

    it "when integration is braintree" do
      result = ChargeSwitch.trace(integration: "braintree")
      pp result.wtf?

      result.success?.must_equal true
      result[:model].charge_id.must_equal 2
      result[:invoice].type.must_equal "braintree"
      result[:invoice].charge_id.must_equal 2
    end

    it "when integration is braintree but save is failing" do
      result = ChargeSwitch.trace(integration: "braintree", save: false)
      pp result.wtf?

      result.failure?.must_equal true
      result[:model].charge_id.must_equal 2
      result[:error].must_equal "Something wrong happened"
    end

    it "when integration is not supported" do
      result = ChargeSwitch.trace(integration: "smoko")
      pp result.wtf?

      result[:error].must_equal "Unsupported bill integration"
    end
  end

  module ChargeSwitchNoSwitch
    extend Trailblazer::Activity::Railway()
    class Braintree < Trailblazer::Activity::Signal; end

    module_function

    def set_model(ctx, integration:, save: true, **)
      ctx[:model] = OpenStruct.new(bill_integration: integration, save: save)
    end

    def integration?(_ctx, model:, **)
      case model.body
        when "stripe"
          Trailblazer::Activity::Right
        when "braintree"
          Braintree
        else
          Trailblazer::Activity::Left
      end
    end

    def stripe_invoice(ctx, model:, **)
      ctx[:invoice] = OpenStruct.new(type: "stripe", charge_id: model.charge_id)
    end

    def braintree(_ctx, model:, **)
      model.charge_id = 2
      model.save ? Braintree : false
    end

    def braintree_invoice(ctx, model:, **)
      ctx[:invoice] = OpenStruct.new(type: "braintree", charge_id: model.charge_id)
    end

    def error(ctx, *)
      ctx[:error] = "Something wrong happened or integration unsupported"
    end

    step method(:set_model)
    step method(:integration?), Output(Braintree, :braintree) => Track(:braintree)
    step method(:stripe_invoice)
    step method(:braintree_invoice), magnetic_to: [:braintree],
                                     Output(:success) => End(:success_bad),
                                     Output(:failure) => End(:failure_bad)

    fail method(:error)
  end
end
