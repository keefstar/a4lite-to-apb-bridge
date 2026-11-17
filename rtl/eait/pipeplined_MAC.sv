module pipelined_MAC #(
    parameter DATA_WIDTH = 8, parameter ACC_WIDTH  = 32
) (
    input  logic clk, rst_n,
    input  logic valid_in, accum_clr,
    input  logic signed [DATA_WIDTH-1:0] A, B,
    output logic valid_out,
    output logic signed [ACC_WIDTH-1:0] result
);

localparam PROD_WIDTH = 2 * DATA_WIDTH;
logic signed [PROD_WIDTH-1:0] prod_stage1;
logic signed [ACC_WIDTH-1:0] prod_ext;

logic valid_stage1, clr_s1;
/**** STAGE 1: MULTIPLICATION ****/
//Datapath: always load, no reset
always_ff @(posedge clk) begin
    prod_stage1 <= A * B;
    clr_s1 <= accum_clr;
end

//Control: reset validity
always_ff @(posedge clk) begin
    if (!rst_n){valid_stage1, valid_out} <= '0;
    else begin
        valid_stage1 <= valid_in; //to tell stage2 to process stored product
        valid_out <= valid_stage1; //tell external world that result was updated using a valid product at this edge.
    end
end

/**** STAGE 2: ACCUMULATION ****/
//Sign-extend product from 16 bits to 32 bits
assign prod_ext = {{(ACC_WIDTH-PROD_WIDTH){prod_stage1[PROD_WIDTH-1]}}, prod_stage1};

// Accumulate or start a new sum
always_ff @(posedge clk) begin
    if (!rst_n)  result <= '0;
    else if (valid_stage1) result <= clr_s1 ? prod_ext : result + prod_ext;
end

endmodule