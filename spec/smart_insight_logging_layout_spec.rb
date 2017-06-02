require 'spec_helper'

RSpec.describe SmartInsightLoggingLayout do
  it 'has a version number' do
    expect(SmartInsightLoggingLayout::VERSION).not_to be nil
  end

  let(:context) { {} }
  let(:prefix) { '' }
  let(:layout) { described_class.new(context: context, prefix: prefix) }

  let(:message) { 'Hello, World!' }
  let(:logger_name) { 'TestLogger' }
  let(:level_name) {  Logging::LEVELS.keys.sample }
  let(:event) { Logging::LogEvent.new(logger_name,  Logging::LEVELS[level_name], message, false) }

  define :json_include do
    match { expect(JSON.parse(actual)).to include expected }
  end

  before(:all) { ::Logging.init unless ::Logging.initialized? }

  describe '#format' do
    subject(:format) { layout.format(event) }

    it { is_expected.to json_include 'timestamp' => event.time.iso8601 }
    it { is_expected.to json_include 'level' => level_name.upcase }
    it { is_expected.to json_include 'logger' => logger_name }
    it { is_expected.to json_include 'hostname' => Socket.gethostname }
    it { is_expected.to json_include 'pid' => Process.pid }

    it { is_expected.to match(/\n$/) }

    context 'when message context is given upon creation' do
      let(:context) { { environment: 'test' } }

      it { is_expected.to json_include 'environment' => 'test' }

      context 'when some part of the context is also present in the message' do
        let(:message) { { environment: 'demo' } }

        it { is_expected.to json_include 'environment' => 'demo' }
      end
    end

    context 'when prefix given' do
      let(:prefix) { 'json: ' }

      it { is_expected.to match(/^json: /) }

      it { is_expected.to match(/"logger":"#{logger_name}"/) }
    end

    context 'when message is a string' do
      let(:message) { 'log message' }

      it { is_expected.to json_include 'message' => message }
    end

    context 'when message is array' do
      let(:message) { [1, 2, 3, 4] }

      it { is_expected.to json_include 'message' => message }
    end

    context 'when message is an exception' do
      let(:message) { StandardError.new('boom') }
      let(:backtrace) { [] }
      before { message.set_backtrace(backtrace) }

      it { is_expected.to json_include 'error' => { 'class' => message.class.to_s, 'message' => message.message, 'backtrace' => message.backtrace } }
      it { is_expected.to json_include 'message' => message.message }

      context 'when the exception has a long backtrace' do
        let(:backtrace) { 1.upto(25).map { |counter| "*line##{counter}*" } }

        it 'only includes the first 20 lines of the backtrace' do
          backtrace.first(20).each { |backtrace_line| expect(format).to include backtrace_line }
          backtrace.last(5).each { |backtrace_line| expect(format).not_to include backtrace_line }
        end
      end
    end

    context 'when mdc is set' do
      before do
        Logging.mdc['X-Session'] = '123abc'
        Logging.mdc['Cookie'] = 'monster'
      end
      after { Logging.mdc.clear }

      it { is_expected.to json_include Logging.mdc.context }

      context 'and one mdc value is deleted during the processing' do
        before { Logging.mdc.delete 'Cookie' }

        it { is_expected.to json_include Logging.mdc.context }
      end

      it 'support the old legacy context in message merge layout' do
        is_expected.to json_include Logging.mdc.context
      end

      context 'when some part of the context is also present in the message' do
        let(:message) { { 'X-Session' => 'qwe456' } }

        it { is_expected.to json_include 'X-Session' => 'qwe456' }
      end
    end

    context 'when message is a legacy JSON encoded message' do
      let(:message) { %({"hello":"world"}) }

      it { is_expected.to json_include 'hello' => 'world' }
    end
  end
end
