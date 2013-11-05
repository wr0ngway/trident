module Trident
  module Utils

    def procline(id, string)
      $0 = "trident[#{id}]: #{string}"
    end

  end
end
