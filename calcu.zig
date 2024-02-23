const std = @import("std");
const stdout = std.io.getStdOut();
const stdin = std.io.getStdIn();
const wout = stdout.writer();
const Allocator = std.mem.Allocator;
const TokenList = std.ArrayList(Token);
const BUFFER_LENGTH = 1024;

const BinOp = struct {
    const Self = @This();
    const Kind = enum {
        add,
        sub,
        mul,
        div,
    };
    precedence: i64,
    kind: Kind,
    fn add() Self {
        return Self{ .precedence = 0, .kind = .add };
    }
    fn sub() Self {
        return Self{ .precedence = 0, .kind = .sub };
    }
    fn mul() Self {
        return Self{ .precedence = 1, .kind = .mul };
    }
    fn div() Self {
        return Self{ .precedence = 1, .kind = .div };
    }
};

const Number = union(enum) {
    int: i64,
    float: f64,
};

const Token = union(enum) {
    bin_op: BinOp,
    number: Number,
    l_parens: void,
    r_parens: void,
    fn toStr(self: Token) []const u8 {
        const defc: []u8 = @constCast("#");
        var buff: []u8 = alloc.alloc(u8, 40) catch defc;
        switch (self) {
            .number => |number| {
                switch (number) {
                    inline else => |val| {
                        buff = std.fmt.bufPrint(buff, "{}", .{val}) catch defc;
                    },
                }
            },
            .bin_op => |op| {
                const c: u8 = switch (op.kind) {
                    .mul => '*',
                    .add => '+',
                    .sub => '-',
                    .div => '/',
                };
                buff = std.fmt.bufPrint(buff, "{c}", .{c}) catch defc;
            },
            else => return defc,
        }
        return buff;
    }
};

fn shuntingYard(tokens: []Token) ![]Token {
    var output_queue = TokenList.initCapacity(alloc, tokens.len) catch unreachable;
    var operator_stack = TokenList.initCapacity(alloc, tokens.len) catch unreachable;
    const ExpToken = enum {
        number_or_lp,
        operand_or_rp,
        any,
    };
    var exp_tok = ExpToken.any;
    for (tokens) |token| {
        switch (token) {
            .number => {
                if (!(exp_tok == .any or exp_tok == .number_or_lp)) {
                    std.log.err("Unexpected token: {}", .{token});
                    return error.UnexpectedToken;
                }
                output_queue.appendAssumeCapacity(token);
                exp_tok = .operand_or_rp;
            },
            .l_parens => {
                if (!(exp_tok == .any or exp_tok == .number_or_lp)) {
                    std.log.err("Unexpected token: {}", .{token});
                    return error.UnexpectedToken;
                }
                operator_stack.appendAssumeCapacity(token);
                exp_tok = .number_or_lp;
            },
            .bin_op => |op| {
                if (!(exp_tok == .any or exp_tok == .operand_or_rp)) {
                    std.log.err("Unexpected token: {}", .{token});
                    return error.UnexpectedToken;
                }
                exp_tok = .number_or_lp;
                while (operator_stack.getLastOrNull()) |prev_op_union| {
                    switch (prev_op_union) {
                        .bin_op => |prev_op| {
                            if (prev_op.precedence >= op.precedence) {
                                output_queue.appendAssumeCapacity(Token{ .bin_op = prev_op });
                                _ = operator_stack.pop();
                            } else {
                                break;
                            }
                        },
                        .l_parens => break,
                        else => unreachable,
                    }
                }
                operator_stack.appendAssumeCapacity(Token{ .bin_op = op });
            },
            .r_parens => {
                if (!(exp_tok == .any or exp_tok == .operand_or_rp)) {
                    std.log.err("Unexpected token: {}", .{token});
                    return error.UnexpectedToken;
                }
                exp_tok = .operand_or_rp;
                loop: while (operator_stack.popOrNull()) |prev_op| {
                    if (std.meta.activeTag(prev_op) == .l_parens) {
                        break :loop;
                    } else {
                        output_queue.appendAssumeCapacity(prev_op);
                    }
                } else {
                    std.log.err("Mismatched brackets", .{});
                    return error.MismatchedBracket;
                }
            },
        }
    }
    while (operator_stack.popOrNull()) |tok| {
        output_queue.appendAssumeCapacity(tok);
    }
    return output_queue.items;
}

fn lexLine(line: []u8) ![]Token {
    var tokens = TokenList.init(alloc);
    var str = std.mem.trimLeft(u8, line, " ");
    while (str.len > 0) {
        switch (str[0]) {
            '+' => {
                try tokens.append(Token{ .bin_op = BinOp.add() });
                str = str[1..];
            },
            '-' => {
                try tokens.append(Token{ .bin_op = BinOp.sub() });
                str = str[1..];
            },
            '*' => {
                try tokens.append(Token{ .bin_op = BinOp.mul() });
                str = str[1..];
            },
            '/' => {
                try tokens.append(Token{ .bin_op = BinOp.div() });
                str = str[1..];
            },
            '(' => {
                try tokens.append(Token{ .l_parens = {} });
                str = str[1..];
            },
            ')' => {
                try tokens.append(Token{ .r_parens = {} });
                str = str[1..];
            },
            '0'...'9' => {
                var has_dot = false;
                var nbuff: [20]u8 = undefined;
                nbuff[0] = str[0];
                var i: usize = 1;
                while (i < str.len and (std.ascii.isDigit(str[i]) or str[i] == '.')) {
                    switch (str[i]) {
                        '.' => {
                            if (!has_dot) {
                                has_dot = true;
                            } else {
                                std.log.err("A number can't have two dots", .{});
                                return error.LexingError;
                            }
                            nbuff[i] = str[i];
                            i += 1;
                        },
                        '0'...'9' => {
                            nbuff[i] = str[i];
                            i += 1;
                        },
                        '_' => {
                            i += 1;
                        },
                        else => {
                            std.log.err("Unexpected `{c}` while trying to parse number", .{str[i]});
                            return error.LexingError;
                        },
                    }
                }
                if (has_dot) {
                    const number = std.fmt.parseFloat(f32, nbuff[0..i]) catch {
                        std.log.err("Expected digit but got {s}", .{nbuff[0..i]});
                        return error.LexingError;
                    };
                    try tokens.append(Token{ .number = .{ .float = number } });
                } else {
                    const number = std.fmt.parseInt(i64, nbuff[0..i], 10) catch {
                        std.log.err("Expected digit but got {s}", .{nbuff[0..i]});
                        return error.LexingError;
                    };
                    try tokens.append(Token{ .number = .{ .int = number } });
                }
                str = str[i..];
            },
            else => {
                std.log.err("Unexpected char `{c}`", .{str[0]});
                return error.LexingError;
            },
        }
        str = std.mem.trimLeft(u8, str, " ");
    }

    return tokens.items;
}

var arena: std.heap.ArenaAllocator = undefined;
var alloc: Allocator = undefined;

pub fn main() !u8 {
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    alloc = arena.allocator();
    defer arena.deinit();

    var line_buff: [BUFFER_LENGTH]u8 = undefined; //[_]u8{0} ** 1024;

    repl_loop: while (true) {
        try wout.print("calcu>", .{});
        const n: usize = try stdin.read(&line_buff);
        const sv = line_buff[0..(n - 1)]; // Trimmed newline
        if (sv.len == 0) continue;
        if (std.mem.eql(u8, sv, "q")) break;
        const tokens = lexLine(sv) catch |err| {
            if (err != error.LexingError) {
                std.log.err("Error while parsing: {s}", .{@errorName(err)});
            }
            continue :repl_loop;
        };
        const rp_tokens = try shuntingYard(tokens);
        for (rp_tokens) |tk| {
            try wout.print("{s} ", .{tk.toStr()});
        }
        _ = try wout.write("\n");
        _ = arena.reset(.retain_capacity);
    }
    return 0;
}
