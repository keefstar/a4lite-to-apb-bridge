module a4lite_apb_bridge # (
  parameter int unsigned AW_DEPTH = 4, W_DEPTH  = 4, AR_DEPTH = 4, R_DEPTH = 4, B_DEPTH = 4, DISPATCH_DEPTH = 4, DATA_WIDTH = 32,  ADDR_WIDTH = 32, TIMEOUT_CYCLES = 16,
  /* ADDRESS DECODER */
  //AMD's PG073 bridge allows the integrator to configure the number of APB peripherals and each peripheral's base and high addresses. The IP then performs the decoding and generates the appropriate PSEL lines.
  //Industry precedent: system integrator defines the memory map; reusable HW implements the decoding
  parameter int unsigned NUM_APB = 4,
  parameter logic [NUM_APB-1:0][ADDR_WIDTH-1:0] BASE_ADDR =  {
    32'h4000_3000,
    32'h4000_2000,
    32'h4000_1000,
    32'h4000_0000
  },
  parameter logic [NUM_APB-1:0][ADDR_WIDTH-1:0] REGION_SIZE = {
    32'h0000_1000,
    32'h0000_1000,
    32'h0000_1000,
    32'h0000_1000
  }
   //track how many bytes a particular address space a peripheral occupies
)(
  a4lite_if.subordinate s_axi, // AXI4-Lite interface on the upstream side of the bridge -- where it acts as AXI4-Lite subordinate
  apb4_if.requester m_apb,
  intr_if.bridge intr  // APB interface on the downstream side of the bridge -- where it acts as an APB requester/manager
);

/************** AXI4-Lite Request/Response structs **************/
typedef struct packed {
  logic [ADDR_WIDTH-1:0] addr;
  logic [2:0] prot;
} axi_addr_t;

typedef struct packed {
  logic [DATA_WIDTH-1:0] data;
  logic [(DATA_WIDTH/8)-1:0] strb;
} axi_data_t;

/************** APB Request/Completer struct **************/
typedef struct packed {
  logic pwrite;
  logic [ADDR_WIDTH-1:0] paddr;
  logic [DATA_WIDTH-1:0] pwdata;
  logic [(DATA_WIDTH/8)-1:0] pstrb;
  logic [2:0] pprot;
} apb_req_t;

typedef struct packed {
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0] rresp;
} axi_rresp_t;

typedef struct packed {
    logic [1:0] bresp;
} axi_bresp_t;

typedef enum logic [1:0] {
  AXI_OKAY = 2'b00,
  AXI_SLVERR = 2'b10,
  AXI_DECERR = 2'b11
} axi_resp_t;

/******************* AW/W *****************/
logic w_full, aw_full, w_empty, aw_empty;
logic w_push, aw_push, w_pop, aw_pop;
logic [$clog2(W_DEPTH):0] w_count;
logic [$clog2(AW_DEPTH):0] aw_count;

axi_data_t w_payload; /* convert raw W channel data from AXI interface into defined AXI data struct */
axi_data_t w_popped; /* to take fields from AXI data struct and create APB request item (for write)*/
axi_addr_t aw_payload, aw_popped;

//AXI4-Lite permits the AXI-subordinate to wait for both AWVALID and WVALID before asserting its READY signals. 
//A compliant manager will not wait for READY before asserting VALID.
logic write_pair_ready;
assign s_axi.WREADY = write_pair_ready;
assign s_axi.AWREADY = write_pair_ready;

assign aw_push = s_axi.AWVALID && s_axi.AWREADY;
assign w_push  = s_axi.WVALID  && s_axi.WREADY;

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) write_pair_ready <= '0;
  else if (write_pair_ready) write_pair_ready <= '0;
  //need to be in correct apb_state, need space in AW/W fifo, need [both] AW/W valid from axi-manager, 
  else if (!block_new_writes && (!aw_full && !w_full) && (s_axi.AWVALID && s_axi.WVALID)) write_pair_ready <= 1'b1;
end


always_comb begin : aw_construct
  aw_payload.addr = s_axi.AWADDR;
  aw_payload.prot = s_axi.AWPROT;
  ///
  w_payload.data = s_axi.WDATA;
  w_payload.strb = s_axi.WSTRB;
end

/* note: fifo implementation has a one-clock-edge read latency because rd_data is registered.*/
sync_fifo #(.DATA_WIDTH($bits(axi_data_t)), .DEPTH(W_DEPTH)
) w_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(w_push), .rd_en(w_pop), .wr_data(w_payload), .rd_data(w_popped),
  .full(w_full), .empty(w_empty), .count(w_count)
);

/* AW buffer FIFO*/
sync_fifo #(.DATA_WIDTH($bits(axi_addr_t)), .DEPTH(AW_DEPTH)
) aw_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(aw_push), .rd_en(aw_pop), .wr_data(aw_payload), .rd_data(aw_popped),
  .full(aw_full), .empty(aw_empty), .count(aw_count)
);

/* small FSM to account for 1 cycle latency for FIFO reads*/
typedef enum logic {
  PAIR_WAIT, //if both FIFOs are non-empty, there are W and AW transfers that can be matched; pop at cycle N, results will be avaliable at N+1;
  PAIR_READY
} pair_state_t;
pair_state_t pair_state, pair_next_state;

/* wait till we are able to request a pop from FIFO, and AW and W are non-empty (and can be matched due to ordering constraint)*/
logic pair_pop; 
assign pair_pop = (pair_state == PAIR_WAIT) && !aw_empty && !w_empty;
assign aw_pop = pair_pop;
assign w_pop  = pair_pop;

logic write_req_valid, write_req_ready, write_req_fire;
assign write_req_ready = grant_write && !dispatch_full;
assign write_req_valid = (pair_state == PAIR_READY); //for arbiter; a complete write request is assembled
assign write_req_fire = write_req_valid && write_req_ready;

always_comb begin : write_pair_comb
  case(pair_state)
    PAIR_WAIT: pair_next_state = (pair_pop) ? PAIR_READY: PAIR_WAIT; //non-empty check
    PAIR_READY: pair_next_state = (write_req_fire) ? PAIR_WAIT : PAIR_READY; //hold the assembled write until it is accepted for dispatch queue.
    default: pair_next_state = PAIR_WAIT;
  endcase
end
always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) begin
    pair_state <= PAIR_WAIT;
  end else pair_state <= pair_next_state;
end

//assemble APB write transfer
apb_req_t write_req;
always_comb begin
  write_req.pwrite = 1'b1;
  write_req.paddr = aw_popped.addr;
  write_req.pwdata = w_popped.data;
  write_req.pstrb = w_popped.strb;
  write_req.pprot = aw_popped.prot;
end

/************* AR *************/
logic ar_full, ar_empty, ar_push, ar_pop;
logic [$clog2(AR_DEPTH):0] ar_count;

assign s_axi.ARREADY = !ar_full && !fault_active;
assign ar_push = s_axi.ARVALID && s_axi.ARREADY;

axi_addr_t ar_payload; /* convert raw AR channel data from AXI interface into defined AXI data struct */
axi_addr_t ar_popped; 
always_comb begin 
  ar_payload.addr = s_axi.ARADDR;
  ar_payload.prot = s_axi.ARPROT;
end
/* AR buffer FIFO*/
sync_fifo #(.DATA_WIDTH($bits(axi_addr_t)), .DEPTH(AR_DEPTH)
) ar_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(ar_push), .rd_en(ar_pop), .wr_data(ar_payload), .rd_data(ar_popped),
  .full(ar_full), .empty(ar_empty), .count(ar_count)
);

typedef enum logic{
  READ_WAIT, READ_READY
} read_state_t;
read_state_t read_state, read_next_state;

logic read_req_valid, read_req_ready, read_req_fire;
assign ar_pop = (read_state == READ_WAIT) && !ar_empty;
assign read_req_valid = (read_state == READ_READY);
assign read_req_ready = grant_read && !dispatch_full;
assign read_req_fire = read_req_valid && read_req_ready;

always_comb begin
  case(read_state)
    READ_WAIT: read_next_state = (ar_pop) ? READ_READY : READ_WAIT;
    READ_READY: read_next_state = (read_req_fire) ? READ_WAIT : READ_READY;
    default: read_next_state = READ_WAIT;
  endcase
end

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) read_state <= READ_WAIT;
  else read_state <= read_next_state;
end

/* construct APB read request */
apb_req_t read_req;
always_comb begin 
  read_req = '0;
  read_req.paddr = ar_popped.addr;
  read_req.pprot = ar_popped.prot;
end



/****** Arbitration *************/
/* arbitration logic: if both read and write requests are here in their fifo, whichever is the very first being put into dispatch queue initiates the bit (flip) of is_write. 
assume it is write so it is made 1. check if dispatch_queue is non-empty -> if there is also a non-empty read buffer (and check also for write), because we just had a write,
the next transaction type we put in is read. if there were no read/read_queue was empty then we just continue adding writes (if there are avaliale)*/

typedef enum logic{ 
  PREFER_READ,
  PREFER_WRITE
 } arb_state_t;
 arb_state_t arb_state, arb_next_state;

 always_comb begin
  case(arb_state)
    PREFER_READ: arb_next_state = (read_req_fire) ? PREFER_WRITE : PREFER_READ;
    PREFER_WRITE: arb_next_state = (write_req_fire) ? PREFER_READ : PREFER_WRITE;
    default: arb_next_state = PREFER_READ;
  endcase
 end

 always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) arb_state <= PREFER_READ;
  else arb_state <= arb_next_state;
 end

 logic grant_write, grant_read;
 always_comb begin 
  grant_read = '0;
  grant_write = '0;
  if (!dispatch_full) begin
    case(arb_state)
      PREFER_READ: begin
        if (read_req_valid) grant_read = 1'b1;
        else if (write_req_valid) grant_write = 1'b1;
      end
    PREFER_WRITE: begin
      if (write_req_valid) grant_write = 1'b1;
      else if (read_req_valid) grant_read = 1'b1;
    end
    endcase
  end
 end
  
 logic dispatch_full, dispatch_pop, dispatch_push, dispatch_empty;
 apb_req_t dispatch_payload, dispatch_popped;
 logic [$clog2(DISPATCH_DEPTH):0] dispatch_count;
 always_comb begin
  dispatch_payload = '0;
  if (read_req_fire) dispatch_payload = read_req;
  else if (write_req_fire) dispatch_payload = write_req;
 end
 assign dispatch_push = read_req_fire || write_req_fire;
 
/* Global dispatch FIFO*/
sync_fifo #(.DATA_WIDTH($bits(apb_req_t)), .DEPTH(DISPATCH_DEPTH)
) dispatch_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(dispatch_push), .rd_en(dispatch_pop), .wr_data(dispatch_payload), .rd_data(dispatch_popped),
  .full(dispatch_full), .empty(dispatch_empty), .count(dispatch_count)
);

/* Support for APB FSM as per AMBA specification, but extend states to support lockdown for faults/timeouts.*/
typedef enum logic [2:0]{
  IDLE, //wait for a request and pop from dispatch FIFO
  CHECK_SPACE, //identify whether it is read/write & check appropriate AXI response FIFO capacity.
  SETUP, //Assert selected PSEL, with PENABLE = 0
  ACCESS, //Assert PENABLE, hold steady all data for transfer wait for PREADY , and detect timeout
  DRAIN, //Preserve the timed-out APB transaction while error-completing buffered AXI requests 
  LOCKDOWN //Keep APB isolated, and await recovery authorization
} apb_state_t;
apb_state_t state, next_state;

//registers to preserve APB transaction that has timed out.
apb_req_t stalled_apb_req;
logic [NUM_APB-1:0] stalled_psel;


logic fault_active;
logic block_new_writes;
assign fault_active = (state == DRAIN) || (state == LOCKDOWN);
assign block_new_writes = fault_active || apb_timeout;

assign intr.fault_irq  = fault_active;
assign intr.fault_addr = stalled_apb_req.paddr;
assign intr.fault_psel = stalled_psel;

logic [$clog2(TIMEOUT_CYCLES)-1:0] TIMEOUT_COUNTER;
logic [NUM_APB-1:0] decoded_PSEL;
logic addr_hit;

/* design supports back-to-back APB transfers at the protocol minimum [under uncongested conditions]*/
//both response FIFOs must have space. If the about-to-be dispatched transaction is a write, its B response FIFO must have at least two free slots.
logic rresp_almost_full, bresp_almost_full;
assign rresp_almost_full = (rresp_count >= R_DEPTH-1);
assign bresp_almost_full = (bresp_count >= B_DEPTH-1);
logic can_start_next;
assign can_start_next = !rresp_full && !bresp_full && (dispatch_popped.pwrite ? !bresp_almost_full : !rresp_almost_full);



//dispatch FIFO needs two possible consumers (normal operation (APB FSM pops requests to execute), fault operation (error draining cntroller pops requests to error-complete))
logic normal_dispatch_pop;
logic fault_dispatch_pop;
assign dispatch_pop = normal_dispatch_pop || fault_dispatch_pop;

always_comb begin
  normal_dispatch_pop = 1'b0;
  next_state = state;
  case (state)
    IDLE: begin
      if (!dispatch_empty) begin
        normal_dispatch_pop = 1'b1;
        next_state = CHECK_SPACE;
      end
    end
    CHECK_SPACE: begin
      if (dispatch_popped.pwrite) begin
        if (!bresp_full) next_state = SETUP;
      end else begin
        if (!rresp_full) next_state = SETUP;
      end
    end
    SETUP: next_state = (addr_hit) ? ACCESS : IDLE; 
    ACCESS:begin
      if (m_apb.PREADY) begin
        if (!dispatch_empty && can_start_next) begin
          normal_dispatch_pop = 1'b1;
          next_state = SETUP;
        end else next_state = IDLE;
      end
      else if (apb_timeout) next_state = DRAIN;
    end
    DRAIN: next_state = (intr.apb_abort_safe || m_apb.PREADY) ? LOCKDOWN : DRAIN;
    LOCKDOWN:  next_state = (cleanup_complete && intr.recovery_auth) ? IDLE : LOCKDOWN;
    default: next_state = IDLE;
  endcase
end

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) begin
    state <= IDLE;
    TIMEOUT_COUNTER <= '0;
  end 
  else begin
    state <= next_state;
    if (state == ACCESS && !m_apb.PREADY && !apb_timeout) TIMEOUT_COUNTER <= TIMEOUT_COUNTER + 1'b1;
    else TIMEOUT_COUNTER <= '0;
  end
end

//clean-up check:
logic cleanup_complete;
assign cleanup_complete =
  aw_empty && w_empty  && ar_empty && //input FIFos empty
 (pair_state == PAIR_WAIT) && (read_state == READ_WAIT) && //no requests in staging registers for AW/W
  dispatch_empty && (fault_state == FAULT_WAIT) && //dispatch FIFO empty and no fault processing taking place
  bresp_empty && rresp_empty && //all resp FIFOs are cleared out
  !bvalid_reg && !rvalid_reg; //no more requests to deliver to AXI manager.

//error controller
typedef enum logic {
  FAULT_WAIT, FAULT_RESP
} fault_state_t;

fault_state_t fault_state, fault_next_state;
logic fault_resp_fire;
assign fault_dispatch_pop = fault_active && (fault_state == FAULT_WAIT) && !dispatch_empty;
assign fault_resp_fire = fault_active && (fault_state == FAULT_RESP) && (dispatch_popped.pwrite ? !bresp_full : !rresp_full); //can AXI SLVERR be generated? 

always_comb begin
  case (fault_state)
    FAULT_WAIT: fault_next_state = (fault_dispatch_pop) ? FAULT_RESP : FAULT_WAIT;
    FAULT_RESP:fault_next_state = (fault_resp_fire) ? FAULT_WAIT : FAULT_RESP;
    default: fault_next_state = FAULT_WAIT;
  endcase
end

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) fault_state <= FAULT_WAIT;
  else fault_state <= fault_next_state;
end


//assign m_apb.PSEL = decoded_psel;
assign m_apb.PSEL = (state == DRAIN) ? stalled_psel : (state == SETUP || state == ACCESS) ? decoded_PSEL : '0;
logic decode_error;
assign decode_error = (state == SETUP && !addr_hit); 
always_comb begin : address_decoder
  decoded_PSEL = '0;
  for (int i = 0; i < NUM_APB; i++)  if (dispatch_popped.paddr >= BASE_ADDR[i] && ((dispatch_popped.paddr-BASE_ADDR[i]) < REGION_SIZE[i])) decoded_PSEL[i] = 1'b1;
  addr_hit = |decoded_PSEL;
  //when to account for unmapped address? where in code?
end

assign m_apb.PENABLE = (state == ACCESS || state == DRAIN);


apb_req_t active_apb_req;
//serves as multiplexer between two possible sources depending on normal vs timeout/
assign active_apb_req = (state == DRAIN) ? stalled_apb_req : dispatch_popped;

always_comb begin : construct_transfer
  m_apb.PWRITE = active_apb_req.pwrite;
  m_apb.PSTRB = active_apb_req.pstrb;
  m_apb.PWDATA= active_apb_req.pwdata;
  m_apb.PPROT= active_apb_req.pprot;
  m_apb.PADDR = active_apb_req.paddr;
end


//response logic to discern normal and apb timeout
logic [$clog2(B_DEPTH):0] bresp_count;
logic apb_done, apb_timeout;
assign apb_done = (state == ACCESS) && m_apb.PREADY;
assign apb_timeout = (state == ACCESS) && !m_apb.PREADY && (TIMEOUT_COUNTER == TIMEOUT_CYCLES - 1);

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) begin
    {stalled_apb_req, stalled_psel} <= '0;
  end else if (apb_timeout) begin
    stalled_apb_req <= dispatch_popped;
    stalled_psel <= decoded_PSEL;
  end
end


/* response */
/////B RESPONSE (CONVERT APB TO AXI)
sync_fifo #(.DATA_WIDTH($bits(axi_bresp_t)), .DEPTH(B_DEPTH)
) b_resp_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(bresp_push), .rd_en(bresp_pop), .wr_data(bresp_payload), .rd_data(bresp_popped),
  .full(bresp_full), .empty(bresp_empty), .count(bresp_count)
);

logic bresp_push, bresp_pop, bresp_empty, bresp_full;
axi_bresp_t bresp_payload, bresp_popped;
assign bresp_push = (apb_done || apb_timeout || decode_error || fault_resp_fire) && dispatch_popped.pwrite;
always_comb begin : construct_bresp
  if (fault_resp_fire) bresp_payload.bresp = AXI_SLVERR;
  else if (apb_timeout) bresp_payload.bresp = AXI_SLVERR; 
  else if (decode_error) bresp_payload.bresp = AXI_DECERR;
  else bresp_payload.bresp =  m_apb.PSLVERR ? AXI_SLVERR : AXI_OKAY;
end

logic bvalid_reg;
assign s_axi.BVALID = bvalid_reg;
assign bresp_pop = !bresp_empty && !bvalid_reg; 
assign s_axi.BRESP = bresp_popped.bresp;

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) bvalid_reg <= '0;
  else begin
    if (bresp_pop) bvalid_reg <= 1'b1;
    else if (bvalid_reg && s_axi.BREADY) bvalid_reg <= 1'b0;
  end
end

///
///R RESPONSE 
sync_fifo #(.DATA_WIDTH($bits(axi_rresp_t)), .DEPTH(R_DEPTH)
) r_resp_buffer (
  .clk(s_axi.ACLK), .resetn(s_axi.ARESETn),
  .wr_en(rresp_push), .rd_en(rresp_pop), .wr_data(rresp_payload), .rd_data(rresp_popped),
  .full(rresp_full), .empty(rresp_empty), .count(rresp_count)
);

logic [$clog2(R_DEPTH):0] rresp_count;
logic rresp_push, rresp_pop, rresp_empty, rresp_full;
axi_rresp_t rresp_payload, rresp_popped;
assign rresp_push = (apb_done || apb_timeout || decode_error || fault_resp_fire) && !dispatch_popped.pwrite;
always_comb begin
  if (fault_resp_fire) begin
    rresp_payload.rdata = '0;
    rresp_payload.rresp = AXI_SLVERR;
  end else if (apb_timeout) begin
    rresp_payload.rdata = '0;
    rresp_payload.rresp = AXI_SLVERR;
  end else if (decode_error) begin
    rresp_payload.rdata = '0;
    rresp_payload.rresp = AXI_DECERR;
  end
  else begin
    rresp_payload.rdata = m_apb.PRDATA;
    rresp_payload.rresp = m_apb.PSLVERR ? AXI_SLVERR : AXI_OKAY;
  end
end

logic rvalid_reg;
assign s_axi.RVALID = rvalid_reg; //from AXI manager
assign rresp_pop = !rresp_empty && !rvalid_reg; //pop when response queue contains read response from APB and current AXI output isn't occupied.
//once the transaction is complete, rvalid_reg does retutn to 0 but immediately becomes 1 again due to the fact we can pop a new response (if queue is non-empty and the sequential logic flow flows as it flows)

//connect FIFO registered output to AXI interface
assign s_axi.RDATA = rresp_popped.rdata;
assign s_axi.RRESP = rresp_popped.rresp;

always_ff @ (posedge s_axi.ACLK) begin
  if (!s_axi.ARESETn) rvalid_reg <= '0;
  else begin
    if (rresp_pop) rvalid_reg <= 1'b1;
    else if (rvalid_reg && s_axi.RREADY) rvalid_reg <= 1'b0;
  end
end

endmodule : a4lite_apb_bridge;
//One important functional detail: you currently stop accepting new writes after a timeout, but your ARREADY remains active during faults. We'll fix that when implementing recovery.


/*


Drain and Lockdown:

Suppose A is the in-flight APB transfer. The dispatch FIFO is also in order of [E,D,C,B] where B is the oldest accepted transaction for dispatch,
and E is most recent accepted to dispatch. B through E can be a mix of read and write transfers. You may also assume there are some transactions in the response FIFOs (completed APB transfers) ready to be
returned to the AXI manager. If A times out, the procedure is systematic.
Preserve a copy of A (We need to hold steady metadata signals and the PSEL assosciated with A as we still do continue with the APB transfer (but will not forward a ghost response that does come))
Since A was otherwise the oldest transaction in progress, we will SLVERR it out first before B through E. Note since A-E can be a mix of read/writes, the response order is relative (If D is a read and B is a write, D could be returned before B as dependent on AXI RREADY and BREADY signals)
Important distinction: those original transactions in the response FIFOs are legitimate responses, and they are returned first,
as dispatch entries are then popped into response FIFOs, space permitting. The original transctions in the response FIFOs will be returned to AXI with their associated DATA and RESP values as is (can be real data + real AXI_OKAY/SLVERR/DECREE).
Additionally, any transactions in the AR and W/AR FIFOs (those that were accepted and waiting to be placed into dispatch) must also be similarly SLVERRed out.
During this clean-up process, no further AXI transactions are accepted (READY signals are deasserted).

apb_abort_safe: Has hardware guaranteed that A's stalled APB operation has been safely terminated?
recovery_authorized: Has the system determined that the bridge is permitted to resume accepting and executing transactions?

Drain -> Lockdown happens under two scenarios: 1) The originally timed-out transaction (A) does complete (PREADY == 1), OR a hardware-connfirmed safe peripheral reset is observed.
If the reset comes before late response arrival, that takes precedence. 

The bridge remains in lockdown until conditions are satisfied:
1) Clean-up to AXI manager has completed.
2) Require authorization and confirmation to resume normal operation (note: is this the same as the hardware-confirmed safe reset exepcted in DRAIN?)

Interrupt Control:
fault_irq: bridge to CPU to notify it that an APB transfer has timed out and the bridge is in containment, and requires further intervention
recovery_auth: CPU to bridge to notify birdge the fault is handled and bridge is authorized to resume safe operation when ready (clean up done)

*/