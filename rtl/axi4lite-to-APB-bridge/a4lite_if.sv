interface a4lite_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int STRB_WIDTH = (DATA_WIDTH/8),
  parameter int PROT_WIDTH = 3
) (
  input logic ACLK, ARESETn //global signals
);

logic [ADDR_WIDTH-1:0] AWADDR, ARADDR; //address registers
logic [DATA_WIDTH-1:0] RDATA, WDATA; //data registers
logic [STRB_WIDTH-1:0] WSTRB; //write strobe
logic [PROT_WIDTH-1:0] ARPROT, AWPROT; // protection bits
logic ARVALID, AWVALID, WVALID, RREADY, BREADY; //signals asserted by manager
logic ARREADY, AWREADY, WREADY, RVALID, BVALID; //handshake signals asserted by slave
logic [1:0] BRESP, RRESP; //response signals

modport manager (
  input ACLK, ARESETn,
  //(AR)
  output ARVALID, ARADDR, ARPROT,
  input ARREADY,
  //(R)
  input RVALID, RRESP, RDATA,
  output RREADY,
  //(AW)
  output AWVALID, AWADDR, AWPROT,
  input AWREADY,
  //(W)
  output WVALID, WDATA, WSTRB,
  input WREADY,
  //(B)
  input BVALID, BRESP,
  output BREADY
);

modport subordinate (
  input ACLK, ARESETn,
  //(AR)
  input ARVALID, ARADDR, ARPROT,
  output ARREADY,
  //(R)
  output RVALID, RRESP, RDATA,
  input RREADY,
  //(AW)
  input AWVALID, AWADDR, AWPROT,
  output AWREADY,
  //(W)
  input WVALID, WDATA, WSTRB,
  output WREADY,
  //(B) 
  output BVALID, BRESP,
  input BREADY
);

//clocking block:


//note directions inside a cb are defined from tb's viewpoint; i/p: siginals tb reads, driven by DUT; o/p: signals the tb drives (read by DUT)
clocking a4l_mgr_drv @ (posedge ACLK);
  default input #1step output #0;
  //(AR)
  output ARVALID, ARADDR, ARPROT;
  input ARREADY;
  //(R)
  input RVALID, RRESP, RDATA;
  output RREADY;
  //(AW)
  output AWVALID, AWADDR, AWPROT;
  input AWREADY;
  //(W)
  output WVALID, WDATA, WSTRB;
  input WREADY;
  //(B)
  input BVALID, BRESP;
  output BREADY;
endclocking

clocking a4l_mon_cb @ (posedge ACLK);
  default input #1step;
  //(AR)
  input ARVALID, ARADDR, ARPROT;
  input ARREADY;
  //(R)
  input RVALID, RRESP, RDATA;
  input RREADY;
  //(AW)
  input AWVALID, AWADDR, AWPROT;
  input AWREADY;
  //(W)
  input WVALID, WDATA, WSTRB;
  input WREADY;
  //(B)
  input BVALID, BRESP;
  input BREADY;
endclocking

endinterface