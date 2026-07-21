const root = @import("galley");

var calls: usize = 0;
var saw_finalized_recovery = false;

pub fn reset() void {
    calls = 0;
    saw_finalized_recovery = false;
}

pub fn callCount() usize {
    return calls;
}

pub fn sawFinalizedRecovery() bool {
    return saw_finalized_recovery;
}

fn recordFinalizedDiagnostic(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    calls += 1;
    saw_finalized_recovery = switch (args.diagnostic) {
        .syntax => |diagnostic| diagnostic.recovery != null,
    };
    return root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
}

pub const syntax_error = recordFinalizedDiagnostic;
pub const syntax_error_lr_state_16_action_19 = recordFinalizedDiagnostic;
