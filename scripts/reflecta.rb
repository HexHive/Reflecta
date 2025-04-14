if Object.const_defined?(:MRUBY_VERSION)
    $hexdigest = SHA1.method(:sha1_hex)
else
    require 'json'
    require 'digest/sha1'
    $hexdigest = Digest::SHA1.method(:hexdigest)
end

if not $init and $LOAD_PATH
    $init = true
    $LOAD_PATH.each do |path|
        Dir.glob(File.join(path, '*.{rb}')).each do |file|
            if file =~ /(gems|irb|line|bundler|uri|csv|psych|mkmf|resolv|yarp|yaml)/; next; end
            begin; require file; rescue; end
        end
    end
end

class Reflecta
    def self.crash()
        Process.kill('ABRT', Process.pid)
    end

    def self.print(str)
        if $fuzzout == nil
            if ENV["fuzzout"]
                $fuzzout = File.open(ENV["fuzzout"], "w")
            else
                $fuzzout = $stdout
            end
        end

        $fuzzout.puts(str)
        $fuzzout.flush
    end

    def self.filter(b)
        begin
            return eval(b)
        rescue
            return false
        end
    end

    def self.builtins()
        builtins = []
        ObjectSpace.each_object do |o|
            if o.is_a?(Module) and not o.ancestors.include?(Exception) and o.respond_to?(:name) and o.name != nil
                builtins.append(o.name)
            end
        end

        return builtins.select { |b| self.filter(b) }
    end

    def self.enumerate()
        self.print(JSON.dump(self.builtins()))
    end

    def self.record(obj, index)
        self.print(JSON.dump(self.reflect(obj, index)[0]))

    end

    def self.reflect(obj, index)
        return [
            "index" => index,
            "kind" => self.kindof(obj),
            "type" => self.typeof(obj),
            "arity" => self.arityof(obj),
            "fields" => self.fieldsof(obj),
            "methods" => self.methodsof(obj),
        ]
    end


    def self.kindof(obj)
        if [Numeric, String, NilClass, TrueClass, FalseClass].any? { |c| obj.is_a?(c) }
            return "primitive"
        elsif obj.respond_to?(:new) and obj.instance_of?(Class)
            return "class"
        elsif obj.respond_to?(:call)
            return "function"
        else
            return "object"
        end
    end

    def self.typeof(obj)
        case self.kindof(obj)
        when "primitive"
            return obj.class.name
        when "class", "function"
            if obj.respond_to?(:name) and obj.name != nil
                return self.kindof(obj) + "." + obj.name
            else
                return self.kindof(obj)
            end
        when "object"
            if obj.class.respond_to?(:name) and obj.class.name != nil
                return "object." + obj.class.name
            else
                return "object"
            end
        end
    end

    def self.arityof(fn)
        if self.kindof(fn) == "class"
            fn = fn.method(:new)
        end
        if fn.respond_to?(:parameters)
            return fn.parameters.filter {|p| p[0] == :req}.size
        else
            return nil
        end
    end

    def self.methodsof(obj)
        if obj.respond_to?(:methods)
            return obj.methods.map {|m| [m, self.arityof(obj.method(m)).to_s]}
        else
            return []
        end
    end

    def self.fieldsof(obj)
        if obj.respond_to?(:constants)
            return obj.constants
        else
            return []
        end
    end
end

# c = (Object.constants.select { |c| !c.to_s.end_with?("Error") }).to_set
# b = Reflecta.builtins.to_set
# puts b - c
