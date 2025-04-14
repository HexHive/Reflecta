class Reflecta {
    static crash() {
        fuzzilli('FUZZILLI_CRASH', 0)
    }

    static builtins(obj = globalThis, path = "globalThis", visited = new Set()) {
        visited.add(obj)

        let paths = [path]
        for (let p of Object.getOwnPropertyNames(obj)) {
            if (visited.has(obj[p]) || !p.match(/^\w+$/) || ["prototype", "length", "arguments", "caller", "name", "Reflecta"].includes(p)) {
                continue
            } else if (Reflecta.kindof(obj[p]) === "primitive") {
                paths.push(path + "." + p)
            } else {
                paths.push(...Reflecta.builtins(obj[p], path + "." + p, visited))
            }
        }

        return paths
    }

    static enumerate() {
        let builtins = Reflecta.builtins().map((b) => b.replace("globalThis.", ""))
        let json = JSON.stringify(builtins)
        Reflecta.print(json)
    }

    static print(str) {
        fuzzilli('FUZZILLI_PRINT', str)
    }

    static record(obj, index) {
        Reflecta.print(JSON.stringify(Reflecta.reflect(obj, index)))
    }

    static reflect(obj, index) {
        return {
            "index": index,
            "kind": Reflecta.kindof(obj),
            "type": Reflecta.typeof(obj),
            "arity": Reflecta.arityof(obj),
            "fields": Reflecta.fieldsof(obj),
            "methods": Reflecta.methodsof(obj),
        }
    }

    static kindof(obj) {
        switch (typeof obj) {
            case "string":
            case "number":
            case "boolean":
            case "bigint":
            case "symbol":
            case "null":
            case "undefined":
                return "primitive"
            case "object":
                return obj === null ? "primitive" : "object"
            case "function":
                if (Object.hasOwn(obj, "prototype") && Object.hasOwn(obj, "name") && obj.name.match(/^[A-Z]\w*$/))
                    return "class"
                else
                    return "function"
            default:
                throw 0
        }
    }

    static typeof(obj) {
        switch (Reflecta.kindof(obj)) {
            case "primitive":
                return (typeof obj)
            case "object":
                if (Object.hasOwn(obj, "constructor") && Object.hasOwn(obj.constructor, "name")) {
                    return "object." + obj.constructor.name
                } else {
                    return "object"
                }
            case "class":
                if (Object.hasOwn(obj, "name")) {
                    return "class." + obj.name
                } else {
                    return "class"
                }
            case "function":
                if (Object.hasOwn(obj, "name")) {
                    return "function." + obj.name
                } else {
                    return "function." + Reflecta.arityof(obj)
                }
        }
    }

    static methodsof(obj) {
        return Object
            .getOwnPropertyNames(obj ?? {})
            .filter((p) => Reflecta.kindof(obj[p]) === 'function')
            .map((p) => [p, Reflecta.arityof(obj[p]).toString()])
    }

    static arityof(fn) {
        if (["class", "function"].includes(Reflecta.kindof(fn)) && Object.hasOwn(fn, "length")) {
            return fn.length >= 0 ? fn.length : null
        } else {
            return null
        }
    }

    static fieldsof(obj) {
        return Object.getOwnPropertyNames(obj ?? {})
    }
}
