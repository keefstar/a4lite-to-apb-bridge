module compute_tile #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int NUM_MACS   = 4
) (
    input logic clk, rst_n,
    input logic valid_in, accum_clr,
    input logic signed [DATA_WIDTH-1:0] A [NUM_MACS],
    input logic signed [DATA_WIDTH-1:0] B [NUM_MACS],
    output logic valid_out,
    output logic signed [ACC_WIDTH-1:0] C [NUM_MACS]
);

    logic [NUM_MACS-1:0] mac_valid_out;
    for (genvar i = 0; i < NUM_MACS; i++) begin : MAC_inst
        pipelined_MAC #(
            .DATA_WIDTH(DATA_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) u_mac (
            .clk(clk), .rst_n(rst_n),
            .valid_in(valid_in), .accum_clr(accum_clr),
            .A(A[i]), .B(B[i]),
            .valid_out(mac_valid_out[i]),
            .result(C[i])
        );
    end
    //All MACs receive identical valid control
    assign valid_out = mac_valid_out[0];

endmodule