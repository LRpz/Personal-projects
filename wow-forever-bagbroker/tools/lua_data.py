"""Data-only reader for Lua table literals.

QuestieDB ships its data as Lua source. This module never executes that source: it tokenizes
it and parses table constructors, strings, numbers, booleans and dotted names. Dotted names
(such as zoneIDs.ELWYNN_FOREST) are resolved from a symbol table supplied by the caller, which is
itself parsed from data files; unknown names resolve to None. Function calls and operators other
than unary minus and numeric addition are skipped and yield None.
"""
import re

_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)
  | (?P<long>\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|[{}\[\]()=,;.:+\-*/%^#<>])
""", re.S | re.X)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def _unescape(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n.isdigit():
                m = re.match(r"\d{1,3}", body[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(_ESCAPES.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tokenize(src, start=0, end=None):
    end = len(src) if end is None else end
    pos, tokens = start, []
    while pos < end:
        m = _TOKEN.match(src, pos)
        if not m:
            raise ValueError("unexpected character %r at %d" % (src[pos], pos))
        kind = m.lastgroup
        text = m.group(0)
        pos = m.end()
        if kind in ("ws", "comment", "ceq", "leq"):
            continue
        if kind == "long":
            eq = len(m.group("leq"))
            body = text[2 + eq:-(2 + eq)]
            if body.startswith("\n"):
                body = body[1:]
            tokens.append(("str", body))
        elif kind == "str":
            tokens.append(("str", _unescape(text[1:-1])))
        elif kind == "num":
            tokens.append(("num", float.fromhex(text) if text[:2].lower() == "0x" and "." in text else (int(text, 16) if text[:2].lower() == "0x" else (float(text) if any(ch in text for ch in ".eE") else int(text)))))
        elif kind == "name":
            tokens.append(("name", text))
        else:
            tokens.append(("op", text))
    return tokens


class Parser:
    def __init__(self, tokens, symbols=None):
        self.t = tokens
        self.i = 0
        self.symbols = symbols or {}

    def peek(self, k=0):
        j = self.i + k
        return self.t[j] if j < len(self.t) else ("eof", None)

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect(self, value):
        tok = self.take()
        if tok[1] != value:
            raise ValueError("expected %r, got %r at token %d" % (value, tok, self.i))

    def skip_balanced(self, open_, close):
        depth = 0
        while True:
            tok = self.take()
            if tok[0] == "eof":
                return
            if tok[1] == open_:
                depth += 1
            elif tok[1] == close:
                depth -= 1
                if depth == 0:
                    return

    def resolve(self, path):
        value = self.symbols
        for part in path:
            if isinstance(value, dict) and part in value:
                value = value[part]
            else:
                return None
        return None if isinstance(value, dict) and path else value

    _BINARY = ("+", "-", "*", "/", "..", "==", "~=", "<", ">", "<=", ">=", "and", "or")

    def expression(self):
        value = self.unary()
        while self.peek()[1] in self._BINARY:
            op = self.take()[1]
            right = self.unary()
            numbers = isinstance(value, (int, float)) and isinstance(right, (int, float))
            if op == "+" and numbers:
                value = value + right
            elif op == "-" and numbers:
                value = value - right
            elif op == ".." and isinstance(value, str) and isinstance(right, str):
                value = value + right
            elif op == "and" and value is not None:
                value = right if value is not False else False
            elif op == "or" and value is not None:
                value = value if value is not False else right
            else:
                value = None  # unknown operand or operator: not data we can resolve
        return value

    def unary(self):
        tok = self.peek()
        if tok[1] == "-":
            self.take()
            v = self.unary()
            return -v if isinstance(v, (int, float)) else None
        if tok[1] in ("not", "#"):
            self.take()
            self.unary()
            return None
        return self.primary()

    def primary(self):
        kind, value = self.take()
        if kind in ("num", "str"):
            return value
        if kind == "op" and value == "{":
            self.i -= 1
            return self.table()
        if kind == "op" and value == "(":
            v = self.expression()
            self.expect(")")
            return v
        if kind == "name":
            if value == "nil":
                return None
            if value == "true":
                return True
            if value == "false":
                return False
            if value == "function":
                # Skip a function literal: blocks open with function/if/do and close with end.
                depth = 1
                while depth and self.peek()[0] != "eof":
                    k, v = self.take()
                    if k == "name" and v in ("function", "if", "do"):
                        depth += 1
                    elif k == "name" and v == "end":
                        depth -= 1
                return None
            path = [value]
            while self.peek()[1] in (".", ":") and self.peek(1)[0] == "name":
                self.take()
                path.append(self.take()[1])
            if self.peek()[1] == "(":
                self.skip_balanced("(", ")")
                return None
            if self.peek()[1] == "[":
                # Indexed access such as t[1]: resolve when possible.
                self.take()
                key = self.expression()
                self.expect("]")
                base = self.resolve(path)
                return base.get(key) if isinstance(base, dict) else None
            return self.resolve(path)
        raise ValueError("unexpected token %r at %d" % ((kind, value), self.i))

    def table(self):
        self.expect("{")
        result, array_index = {}, 1
        while self.peek()[1] != "}":
            tok = self.peek()
            if tok[1] == "[":
                self.take()
                key = self.expression()
                self.expect("]")
                self.expect("=")
                value = self.expression()
                if key is not None:
                    result[key] = value
            elif tok[0] == "name" and self.peek(1)[1] == "=":
                key = self.take()[1]
                self.take()
                result[key] = self.expression()
            else:
                value = self.expression()
                result[array_index] = value
                array_index += 1
            if self.peek()[1] in (",", ";"):
                self.take()
            elif self.peek()[1] != "}":
                raise ValueError("expected , or } at token %d: %r" % (self.i, self.peek()))
        self.expect("}")
        return result


def parse_table_at(src, brace_pos, symbols=None):
    """Parse the table constructor whose '{' is at brace_pos."""
    tokens = tokenize(src, brace_pos)
    return Parser(tokens, symbols).table()


def parse_return_table(src, symbols=None):
    """Parse 'return { ... }' (the body of a QuestieDB data string)."""
    m = re.search(r"\breturn\s*\{", src)
    if not m:
        raise ValueError("no return table")
    return parse_table_at(src, m.end() - 1, symbols)


def find_assigned_table(src, pattern, symbols=None):
    """Parse the table assigned by the first match of pattern (regex ending right before '{')."""
    m = re.search(pattern + r"\s*\{", src)
    if not m:
        raise ValueError("pattern not found: " + pattern)
    return parse_table_at(src, m.end() - 1, symbols)


def long_strings_assigned(src, pattern):
    """Yield (name, body) for long-bracket strings assigned by names matching pattern."""
    for m in re.finditer(r"(%s)\s*=\s*\[(=*)\[" % pattern, src):
        eq = m.group(2)
        start = m.end()
        end = src.index("]" + eq + "]", start)
        yield m.group(1), src[start:end]


def to_list(table):
    """Convert a parsed array-like dict {1: a, 2: b} to a list."""
    if not isinstance(table, dict):
        return []
    return [table[i] for i in range(1, len(table) + 1) if i in table]
