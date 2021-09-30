module Logtail
  module Util
    class Encoding
      def self.force_utf8_encoding(data)
        if data.respond_to?(:force_encoding)
          data.dup.force_encoding('UTF-8')
        elsif data.respond_to?(:transform_values)
          data.transform_values { |val| Logtail::Util::Encoding.force_utf8_encoding(val) }
        else
          data
        end
      end
    end
  end
end
