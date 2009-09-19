class << ActiveRecord::Base
  # any 32-bit integer will do, yours should be uniq if you don't want other
  # people to be able to decode your ids
  @@acts_as_obfuscated_mask = 0x7326b443
  cattr_accessor :acts_as_obfuscated_mask

  # numbers must not repeate or else bad bad things will happen
  @@acts_as_obfuscated_base_lookup = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  cattr_accessor :acts_as_obfuscated_base_lookup

  def acts_as_obfuscated(opts={})
    # install the class methods
    self.extend(ActsAsObfuscated::ClassMethods)
    # install the instance methods
    self.send(:include, ActsAsObfuscated::InstanceMethods)
  end
end

module ActsAsObfuscated
  module Vars
  end

  module InstanceMethods
    include Vars

    def eid
      return nil unless self.id
      # obfuscate
      id = self.id ^ ActiveRecord::Base.acts_as_obfuscated_mask
      # reorder
      id =
        ((id      ) & 0xff) << 24 |
        ((id >>  8) & 0xff) << 16 |
        ((id >> 16) & 0xff) <<  8 |
        ((id >> 24) & 0xff)
      ret = ''
      # dec -> base
      lookup = ActiveRecord::Base.acts_as_obfuscated_base_lookup
      num = lookup.length
      begin
        rem = id % num
        ret += lookup[rem,1]
        id = (id - rem) / num
      end until (id <= 0)
      # the eid is the converted value prefixed by the first char of the
      # classname, this is to ensure that we always have at least one
      ret.reverse
    end

    def to_param
      self.eid
    end
  end

  module ClassMethods
    include Vars

    def eid_to_id(eid)
      return nil unless eid
      # have to make a copy of the string here or else we'll mess up the
      # source
      eid = String.new(eid.to_s)
      eid.gsub!(/[-\?&].*$/, '')
      return nil unless eid =~ /^[\dA-Za-z]+$/
        ret = 0
      # base -> dec
      lookup = ActiveRecord::Base.acts_as_obfuscated_base_lookup
      num = lookup.length
      begin
        char = eid.slice!(0, 1)
        pos = lookup.index(char)
        raise ArgumentError, "invalid eid character: #{char}" unless (pos)
        ret = (ret * num) + pos
      end until (eid.length <= 0)
      # un-reorder
      ret =
        ((ret      ) & 0xff) << 24 |
        ((ret >>  8) & 0xff) << 16 |
        ((ret >> 16) & 0xff) <<  8 |
        ((ret >> 24) & 0xff)
      # un-obfuscate
      ret ^ ActiveRecord::Base.acts_as_obfuscated_mask
    end

    def find(*args)
        options = args.extract_options!
        validate_find_options(options)
        set_readonly_option!(options)

        first = args.first
        case args.first
          when :first then find_initial(options)
          when :last  then find_last(options)
          when :all   then find_every(options)
          else
            if first.kind_of?(Fixnum) or first =~ /^\d+$/ then
              # id
              find_from_ids(args, options)
            elsif first.kind_of?(Array) then
              # TODO: support mixed arrays?
              if first.first.kind_of?(Fixnum) or first.first =~ /^\d+$/ then
                # ids
                find_from_ids(args, options)
              else
                # eids
                find_by_eid(args, options)
              end
            else
              # eid
              find_by_eid(args, options)
            end
        end
    end

    def find_by_eid(eid, *args)
      id = nil
      if eid.kind_of? Array
        id = eid.collect { |eid| eid_to_id(eid) }
      else
        id = eid_to_id(eid)
      end
      find(id, *args)
    end

    alias_method(:find_by_eids, :find_by_eid)
  end
end
