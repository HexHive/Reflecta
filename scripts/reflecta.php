<?php

if ($init == null) {
    $reflecta = new class() {
        var $fuzzout = null;

        function crash() {
            $pid = getmypid();
            exec("kill -9 $pid");
        }

        function print($s) {
            if ($this->fuzzout == null) {
                if (empty(getenv("fuzzout"))) {
                    $this->fuzzout = STDOUT;
                } else {
                    $this->fuzzout = fopen(getenv("fuzzout"), "w");
                }
            }
            fwrite($this->fuzzout, $s . "\n");
            fflush($this->fuzzout);
        }

        function builtins() {
            $fns = get_defined_functions();
            $cls = get_declared_classes();

            return array_merge($fns["internal"], $cls);
        }

        function enumerate() {
            $this->print(json_encode($this->builtins()));
        }

        function reflect($obj, $index) {
            return [
                "index" => $index,
                "kind" => $this->kindof($obj),
                "type" => $this->typeof($obj),
                "arity" => $this->arityof($obj),
                "fields" => $this->fieldsof($obj),
                "methods" => $this->methodsof($obj),
            ];
        }

        function record($obj, $index) {
            $this->print(json_encode($this->reflect($obj, $index)));
        }

        function kindof($obj) {
            $ty = gettype($obj);
            if ($ty == "string") {
                if (class_exists($obj)) {
                    return "class";
                } else if (function_exists($obj)) {
                    return "function";
                } else {
                    return "primitive";
                }
            } else if ($ty == "object") {
                return "object";
            } else {
                return "primitive";
            }
        }

        function typeof($obj) {
            switch ($this->kindof($obj)) {
                case "primitive":
                    return gettype($obj);
                case "object":
                    return (new ReflectionObject($obj))->getName();
                case "class":
                    return "class." . (new ReflectionClass($obj))->getName();
                case "function":
                    return (new ReflectionFunction($obj))->getName();
            }
        }

        function arityof($fn) {
            switch ($this->kindof($fn)) {
                case "class":
                    return (new ReflectionClass($fn))->getConstructor()?->getNumberOfRequiredParameters();
                case "function":
                    return (new ReflectionFunction($fn))->getNumberOfRequiredParameters();
            }

            return null;
        }

        function fieldsof($obj) {
            $h = function($p) {
                return $p["name"];
            };
            switch ($this->kindof($obj)) {
                case "object":
                    return array_map($h, (new ReflectionObject($obj))->getProperties());
                case "class":
                    return array_map($h, (new ReflectionClass($obj))->getProperties());
                default:
                    return [];
            }
        }


        function methodsof($obj) {
            $h = function ($m) {
                return [$m->getName(), (string) $m->getNumberOfRequiredParameters()];
            };

            switch ($this->kindof($obj)) {
                case "object":
                    return array_map($h, (new ReflectionObject($obj))->getMethods());
                case "class":
                    return array_map($h, (new ReflectionClass($obj))->getMethods());
                default:
                    return [];
            }
        }
    };

    foreach ($reflecta->builtins() as $b) {
        define($b, $b);
    }

    $init = true;
}
