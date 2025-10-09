// Minimal Objective-C runtime bindings for ZNotify
// Zero external dependencies - direct C runtime calls only

const std = @import("std");

// Import Objective-C runtime C headers
const c = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

/// Objective-C class wrapper
pub const Class = struct {
    value: c.Class,

    /// Send a message to this class (class method)
    pub fn msgSend(self: Class, comptime RetType: type, selector: [:0]const u8, args: anytype) RetType {
        const sel = c.sel_registerName(selector.ptr);
        const target: c.id = @ptrCast(@alignCast(self.value));
        return msgSendImpl(RetType, target, sel, args);
    }
};

/// Objective-C object wrapper
pub const Object = struct {
    value: c.id,

    /// Send a message to this object (instance method)
    pub fn msgSend(self: Object, comptime RetType: type, selector: [:0]const u8, args: anytype) RetType {
        const sel = c.sel_registerName(selector.ptr);
        return msgSendImpl(RetType, self.value, sel, args);
    }

    /// Get a property value from this object
    /// This is a helper for accessing properties that returns structs
    pub fn getProperty(self: Object, comptime T: type, comptime propertyName: [:0]const u8) T {
        // For now, we just use msgSend with the property name as selector
        // Most Cocoa properties have implicit getters with the same name
        return self.msgSend(T, propertyName, .{});
    }
};

/// Get an Objective-C class by name
pub fn getClass(name: [:0]const u8) ?Class {
    const class = c.objc_getClass(name.ptr) orelse return null;
    return Class{ .value = class };
}

/// Build a function type for objc_msgSend based on the arguments
fn MsgSendFn(comptime Return: type, comptime Args: type) type {
    const args_info = @typeInfo(Args).@"struct";
    std.debug.assert(args_info.is_tuple);

    // Build up our parameter types
    const Fn = std.builtin.Type.Fn;
    const params: []Fn.Param = params: {
        var acc: [args_info.fields.len + 2]Fn.Param = undefined;

        // First two arguments are always target (id) and selector (SEL)
        acc[0] = .{ .type = c.id, .is_generic = false, .is_noalias = false };
        acc[1] = .{ .type = c.SEL, .is_generic = false, .is_noalias = false };

        // Remaining arguments come from the args tuple
        for (args_info.fields, 0..) |field, i| {
            acc[i + 2] = .{
                .type = field.type,
                .is_generic = false,
                .is_noalias = false,
            };
        }

        break :params &acc;
    };

    return @Type(.{
        .@"fn" = .{
            .calling_convention = .c,
            .is_generic = false,
            .is_var_args = false,
            .return_type = Return,
            .params = params,
        },
    });
}

/// Core msgSend implementation
fn msgSendImpl(comptime RetType: type, target: c.id, sel: c.SEL, args: anytype) RetType {
    // Handle Object return type specially - we need to return c.id internally
    const is_object = RetType == Object;
    const RealReturn = if (is_object) c.id else RetType;

    // Build the function type based on the actual arguments
    const Fn = MsgSendFn(RealReturn, @TypeOf(args));

    // Cast objc_msgSend to the proper function pointer type
    const msg_send_ptr: *const Fn = @ptrCast(&c.objc_msgSend);

    // Call with target, selector, and all args
    const result = @call(.auto, msg_send_ptr, .{ target, sel } ++ args);

    // Wrap in Object if needed
    if (is_object) {
        return Object{ .value = result };
    }

    return result;
}

// Objective-C Block support
// Based on: https://github.com/llvm/llvm-project/blob/main/compiler-rt/lib/BlocksRuntime/Block_private.h

/// Block descriptor structure
const BlockDescriptor = extern struct {
    reserved: c_ulong = 0,
    size: c_ulong,
    copy_helper: ?*const fn (dst: *anyopaque, src: *anyopaque) callconv(.c) void = null,
    dispose_helper: ?*const fn (src: *anyopaque) callconv(.c) void = null,
    signature: ?[*:0]const u8 = null,
};

/// Block flags
const BlockFlags = packed struct(c_int) {
    _unused: u23 = 0,
    noescape: bool = false,
    _unused_2: u1 = 0,
    copy_dispose: bool = false,
    ctor: bool = false,
    _unused_3: u1 = 0,
    global: bool = false,
    stret: bool = false,
    signature: bool = false,
    _unused_4: u1 = 0,
};

// Block class pointers
const NSConcreteStackBlock = @extern(*opaque {}, .{ .name = "_NSConcreteStackBlock" });

/// Create a simple block with no captures for use as a completion handler
pub fn makeBlock(comptime Fn: type, func: *const Fn) BlockLiteral(Fn) {
    return BlockLiteral(Fn).init(func);
}

/// Block literal structure - this is what gets passed to Objective-C methods
fn BlockLiteral(comptime Fn: type) type {
    return extern struct {
        isa: *anyopaque,
        flags: BlockFlags,
        reserved: c_int = 0,
        invoke: *const Fn,
        descriptor: *const BlockDescriptor,

        const Self = @This();

        // Static descriptor for this block type
        const descriptor_instance = BlockDescriptor{
            .reserved = 0,
            .size = @sizeOf(Self),
        };

        pub fn init(func: *const Fn) Self {
            return Self{
                .isa = NSConcreteStackBlock,
                .flags = .{},
                .invoke = func,
                .descriptor = &descriptor_instance,
            };
        }
    };
}
