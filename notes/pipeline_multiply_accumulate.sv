module pipeline_multiply_accumulate #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32     // must be > 2*DATA_WIDTH
) (
    input  logic clk, rst_n,
    input  logic valid_in, accum_clr,
    input  logic [DATA_WIDTH-1:0] A, B,
    output logic valid_out,
    output logic [ACC_WIDTH-1:0]  result
);

  localparam PW = 2*DATA_WIDTH;   // product width
  logic [PW-1:0] prod_s1;
  logic valid_s1, clr_s1;

  // Stage 1 datapath: always load, no reset
  // Explanation: the alternative was putting these inside the reset if/else:
  //
  //   if (!rst_n) begin
  //     clr_s1  <= 1'b0;
  //   end else begin
  //     prod_s1 <= A * B;
  //     clr_s1  <= accum_clr & valid_in;
  //   end
  //
  // Problems with that:
  //   1) prod_s1 isn't assigned in the reset branch, so it must HOLD its old
  //      value during reset -> the tool adds a hidden 2:1 "remember" mux on
  //      every bit (16 muxes). The reset 'if' acts as an enable.
  //   2) clr_s1's reset and the '& valid_in' are wasted hardware.
  // Why it's safe to drop them: these are pass-through data. Nobody reads
  // prod_s1 or clr_s1 unless valid_s1 == 1, and valid_s1 IS reset to 0.
  // So garbage in them during/after reset is never used.
  // Rule: data always loads; the valid bit says when it's real.
  always_ff @(posedge clk) begin
    prod_s1 <= A * B;
    clr_s1  <= accum_clr;
  end

  // Control: reset only here
  // Explanation: the alternative was one big always_ff that reset EVERYTHING
  // (control + data together). Valid bits MUST be reset: after reset, the
  // pipeline must be empty so no garbage sample is ever treated as real.
  // Keeping control in its own block makes it obvious which registers need
  // reset (control) and which don't (data).
  // valid_in -> valid_s1 -> valid_out: the valid bit travels down the
  // pipeline one stage per cycle, alongside its data.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1  <= 1'b0;
      valid_out <= 1'b0;
    end else begin
      valid_s1  <= valid_in;
      valid_out <= valid_s1;
    end
  end

  // Stage 2 adder, split in two:
  //   low half  = real add (product is only PW bits wide)
  //   high half = just an increment by the carry
  // Explanation: the alternative was one full-width add:
  //
  //   result + prod_s1     // 32-bit add
  //
  // But prod_s1 is only 16 bits, so its upper 16 bits are always 0. The top
  // half of the sum is really "old top half + carry", an increment, which
  // is simpler than a full add. Writing it explicitly gave a small win in
  // both area and speed (v3: 4009 um^2 / 185 MHz -> v4: 3999 um^2 / 189 MHz).
  // The win was small because the tool was already mostly doing this itself.
  // Timing report lesson: the critical path was a chain of maj3 cells =
  // a ripple-carry adder. maj3 = the carry-out of a full adder.
  logic c_lo;
  logic [PW-1:0] sum_lo;
  logic [ACC_WIDTH-PW-1:0] sum_hi;
  assign {c_lo, sum_lo} = result[PW-1:0] + prod_s1;
  assign sum_hi         = result[ACC_WIDTH-1:PW] + c_lo;

  // Stage 2: result is real state, so it keeps reset AND hold
  always_ff @(posedge clk) begin
    if (!rst_n) result <= '0;
    else if (valid_s1) result <= clr_s1 ? {{(ACC_WIDTH-PW){1'b0}}, prod_s1} : {sum_hi, sum_lo};
    // Explanation: the area rules above do NOT apply here. result is not
    // pass-through data, it's the running sum (STATE). The spec requires:
    //   - "rst_n sets result to 0"            -> reset is needed
    //   - "in every other cycle result holds" -> the hold mux is needed
    // So this register keeps both, on purpose.
    //
    // Tried alternative (v2), clearing BEFORE the adder:
    //   result <= (clr_s1 ? '0 : result) + prod_s1;
    // Same function, slightly smaller, but speed dropped from 257 to 126 MHz.
    // Lesson: RTL changes can shift the tool's choices in ways that are hard
    // to predict. Always check the timing report, don't guess.
    //
    // Why clr REPLACES the sum (not "clear to 0, then add next cycle"):
    // replacing lets a new job start on the very same cycle, with no bubble.
  end

endmodule

// Version history (same function, different tradeoffs):
//   v1: one big block, reset on everything   4249 um^2  257 MHz  (fastest)
//   v2: clear before adder                   4055 um^2  126 MHz  (bad trade)
//   v3: area rules applied                   4009 um^2  185 MHz
//   v4: v3 + split adder                     3999 um^2  189 MHz  (smallest)
// Key takeaway: area vs speed is a tradeoff curve. Pick based on what the
// design needs.