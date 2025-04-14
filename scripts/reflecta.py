import os, sys, json, hashlib, builtins

if sys.implementation.name == "micropython":
    import array, binascii, builtins, cmath, collections, errno, heapq, io, math, re, select, struct, btree, framebuf, uctypes, micropython
elif sys.implementation.name == "cpython":
    import importlib, ctypes
    for n in sys.builtin_module_names:
        globals()[n] = importlib.import_module(n)

class Reflecta:
    fuzzout = None
    modtype = type(builtins)

    def crash():
        if sys.implementation.name == "cpython":
            os.kill(os.getpid(), 9)
        elif sys.implementation.name == "micropython":
            import machine
            machine.Signal(9).on()

    def print(s):
        if Reflecta.fuzzout is None:
            if os.getenv("fuzzout"):
                Reflecta.fuzzout = open(os.getenv("fuzzout"), "w")
            else:
                Reflecta.fuzzout = sys.stdout

        Reflecta.fuzzout.write(str(s) + "\n")
        Reflecta.fuzzout.flush()

    def enumerate():
        paths = []
        for m in globals().values():
            if type(m) == Reflecta.modtype:
                paths.extend(Reflecta.builtins(m, m.__name__))

        for p in paths:
            b = eval(p)
            print(p, Reflecta.kindof(b))

        Reflecta.print(json.dumps(paths))


    def reflect(obj, index):
        return {
            "index": index,
            "kind": Reflecta.kindof(obj),
            "type": Reflecta.typeof(obj),
            "arity": Reflecta.arityof(obj),
            "fields": Reflecta.fieldsof(obj),
            "methods": Reflecta.methodsof(obj),
        }

    def record(obj, index):
        Reflecta.print(json.dumps(Reflecta.reflect(obj, index)))

    def filter(b):
        try:
            return Reflecta.kindof(eval(b)) != "primitive"
        except:
            return False

    def builtins(m, path, visited=set()):
        visited.add(id(m))

        paths = [path]
        for n in dir(m):
            attr = getattr(m, n)
            if id(attr) in visited or n.startswith("_"):
                continue
            elif isinstance(attr, Reflecta.modtype):
                paths.extend(Reflecta.builtins(attr, path + "." + n))
            else:
                paths.append(path + "." + n)

        return [p for p in paths if Reflecta.filter(p)]

    def kindof(obj):
        if type(obj) in [builtins.str, builtins.int, builtins.float]:
            return "primitive"
        elif type(obj).__name__ == "type":
            return "class"
        elif "function" in type(obj).__name__ or callable(obj):
            return "function"
        else:
            return "object"

    def typeof(obj):
        kind = Reflecta.kindof(obj)
        if kind == "primitive":
            return type(obj).__name__
        elif kind in ["class", "function"]:
            if hasattr(obj, "__name__") and obj.__name__:
                return obj.__name__
            else:
                return kind
        else:
            if hasattr(obj, "__class__") and hasattr(obj.__class__, "__name__"):
                return obj.__class__.__name__

    def fieldsof(obj):
        return dir(obj)

    def methodsof(obj):
        return [(m, "null") for m in dir(obj) if Reflecta.kindof(getattr(obj, m)) == "function"]

    def arityof(obj):
        return None

# Reflecta.enumerate()
# try:
#     raise Exception()
# except:
#     pass
