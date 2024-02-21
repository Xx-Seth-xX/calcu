const std = @import("std");
const stdout = std.io.getStdOut();
const stdin = std.io.getStdIn();
const wout = stdout.writer();
const BUFFER_LENGTH = 1024;

const TokenType = enum {
    op_plus,
    op_minus,
    op_mul,
    op_div,
    open_parens,
    closing_parens,
    int,
};

const Token = union(TokenType) {
    op_plus: void,
    op_minus: void,
    op_mul: void,
    op_div: void,
    open_parens: void,
    closing_parens: void,
    int: i64,
};

fn parseLine(token_buff: []Token, line: []u8) ![]Token {
    var i: usize = 0;
    var str = std.mem.trimLeft(u8, line, " ");
    while (str.len > 0) : (i += 1) {
        switch (str[0]) {
            '+' => {
                token_buff[i] = Token{ .op_plus = {} };
                str = str[1..];
            },
            '-' => {
                token_buff[i] = Token{ .op_minus = {} };
                str = str[1..];
            },
            '*' => {
                token_buff[i] = Token{ .op_mul = {} };
                str = str[1..];
            },
            '/' => {
                token_buff[i] = Token{ .op_div = {} };
                str = str[1..];
            },
            '(' => {
                token_buff[i] = Token{ .open_parens = {} };
                str = str[1..];
            },
            ')' => {
                token_buff[i] = Token{ .closing_parens = {} };
                str = str[1..];
            },
            '0'...'9' => {
                var nbuff: [20]u8 = undefined;
                nbuff[0] = str[0];
                var c: usize = 1;
                while (c < str.len and std.ascii.isDigit(str[c])) {
                    nbuff[c] = str[c];
                    c += 1;
                }
                const number = std.fmt.parseInt(i64, nbuff[0..c], 10) catch {
                    std.log.err("Expected number but got {s}", .{nbuff[0..c]});
                    return error.ParsingError;
                };
                token_buff[i] = Token{ .int = number };
                str = str[c..];
            },
            else => {
                std.log.err("Unexpected char `{c}`", .{str[0]});
                return error.ParsingError;
            },
        }
        str = std.mem.trimLeft(u8, str, " ");
    }

    return token_buff[0..i];
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const token_buff = try alloc.alloc(Token, 64);

    var line_buff: [BUFFER_LENGTH]u8 = undefined; //[_]u8{0} ** 1024;

    while (true) {
        try wout.print("calcu>", .{});
        const n: usize = try stdin.read(&line_buff);
        const sv = line_buff[0..(n - 1)]; // Trimmed newline
        if (sv.len == 0) continue;
        if (std.mem.eql(u8, sv, "quit")) break;
        const tokens = parseLine(token_buff, sv) catch blk: {
            std.log.err("Invalid command", .{});
            break :blk &[0]Token{};
        };
        for (tokens) |token| {
            std.debug.print("{}\n", .{token});
        }
    }
    return 0;
}
