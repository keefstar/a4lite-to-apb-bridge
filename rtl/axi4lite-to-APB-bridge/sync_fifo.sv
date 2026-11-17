module sync_fifo #(
    parameter DATA_WIDTH = 8, parameter DEPTH      = 8
) (
    input  logic clk, resetn,
    input  logic  wr_en, rd_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic full, empty,
    output logic [$clog2(DEPTH):0] count
);

  localparam ADDR_WIDTH = $clog2(DEPTH);
  logic wr_fire, rd_fire;
  assign wr_fire = wr_en && !full;
  assign rd_fire = rd_en && !empty;
  logic [DATA_WIDTH - 1:0] arr [0:DEPTH -1];
  logic [ADDR_WIDTH:0] wr_ptr, rd_ptr; //note extra bit to track full/empty status

  assign empty = (wr_ptr == rd_ptr);
  assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

  always_ff @ (posedge clk) begin
    if (!resetn) begin
      {count, rd_data} <= '0;
      {wr_ptr, rd_ptr}  <= '0;
      //empty <= 1'b1;
    end else begin
      //note HW result of case statement: synthesis treats this as a parallel structure; all conditions evaluated at first
      //if using if-else chain, priority logic is assumed. syntheis builds cascading multiplexers.
      case ({wr_fire, rd_fire})
      2'b00: ;//do nothing;
      2'b01:  begin
        //read_only
        rd_data <= arr[rd_ptr[ADDR_WIDTH-1:0]];
        rd_ptr <= rd_ptr + 1'b1;
        count <= count - 1'b1;
      end
      2'b10: begin
        arr[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
        count <= count + 1'b1;
      end
      2'b11: begin
        rd_data <= arr[rd_ptr[ADDR_WIDTH-1:0]];
        rd_ptr <= rd_ptr + 1'b1;
        arr[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      default: ;
      endcase
    end
  end
endmodule

//NOTE: Fifo asserts full signals to sender. The design must handle backpressure so that no jobs are lost. Write thsi design constraint, and enforce check via DV.
