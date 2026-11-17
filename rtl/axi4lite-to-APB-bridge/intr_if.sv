
interface intr_if #(
    parameter int unsigned NUM_APB = 1,
    parameter int unsigned ADDR_WIDTH = 32
) (
    input logic clk
);

    logic fault_irq;
    logic [ADDR_WIDTH-1:0] fault_addr;
    logic [NUM_APB-1:0] fault_psel;

    logic apb_abort_safe;
    logic recovery_auth;

    // Bridge perspective
    modport bridge (
        output fault_irq,
        output fault_addr, fault_psel,
        input  apb_abort_safe, recovery_auth
    );

    modport controller (
        input  fault_irq,
        input  fault_addr, fault_psel,
        output apb_abort_safe, recovery_auth
    );

    clocking intr_dr_cb @(posedge clk);
        default input #1step output #0;
        input  fault_irq;
        input  fault_addr, fault_psel;
        output apb_abort_safe, recovery_auth;
    endclocking

    clocking intr_mon_cb @(posedge clk);
        default input #1step output #0;
        input fault_irq, fault_addr, fault_psel;
        input apb_abort_safe, recovery_auth;
    endclocking

endinterface
