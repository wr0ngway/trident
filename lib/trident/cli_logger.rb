# setup our own logger for cli so that we don't lose it when
# we preload environment for workers
module Trident
  module CLILogger

    extend ActiveSupport::Concern

    def self.trident_logger
      @trident_logger ||= ::Logger.new(STDOUT)
    end

    def self.trident_logger=(logger)
      @trident_logger = logger
    end

    module ClassMethods
      def logger
        Trident::CLILogger.trident_logger
      end
    end

  end
end
