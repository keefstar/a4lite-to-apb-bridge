interface apb4_if # (
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_COMPLETERS = 1,
  parameter int STRB_WIDTH = (DATA_WIDTH/8),
  parameter int PROT_WIDTH = 3
) (
  input logic PCLK, PRESETn
);

logic [ADDR_WIDTH-1:0] PADDR;
logic [DATA_WIDTH-1:0] PRDATA, PWDATA;
logic PENABLE, PWRITE, PREADY, PSLVERR;
logic [NUM_COMPLETERS-1:0] PSEL;
//APB4 additions:
logic [STRB_WIDTH-1:0] PSTRB;
logic [PROT_WIDTH-1:0] PPROT;

//bridge perspective
modport requester(
  input PCLK, PRESETn,
  output PADDR, PSEL, PENABLE, PWRITE, PWDATA,
  output PSTRB, PPROT,
  input PRDATA, PREADY, PSLVERR
);

modport completer(
  input PCLK, PRESETn,
  input PADDR, PSEL, PENABLE, PWRITE, PWDATA,
  input PSTRB, PPROT,
  output PRDATA, PREADY, PSLVERR
);

clocking apb4_mon_cb @ (posedge PCLK);
  default input #1step;
  input PADDR, PSEL, PENABLE, PWRITE, PWDATA;
  input PSTRB, PPROT;
  input PRDATA, PREADY, PSLVERR;
endclocking : apb4_mon_cb

clocking apb4_drv_req_cb @(posedge PCLK);
  default input #1step output #0;
  output PADDR, PSEL, PENABLE, PWRITE, PWDATA;
  output PSTRB, PPROT;
  input PRDATA, PREADY, PSLVERR;
endclocking :apb4_drv_req_cb

//for completer
clocking apb4_drv_com_cb @(posedge PCLK);
  default input #1step output #0;
  input PADDR, PSEL, PENABLE, PWRITE, PWDATA;
  input PSTRB, PPROT;
  output PRDATA, PREADY, PSLVERR;
endclocking :apb4_drv_com_cb



endinterface

/*

APB Wait States and Error Responses:
Not every peripheral (EAIT here) can answer in one cycle.

1) An APB transfer completes at the rising edge where PSEL, PENABLE and PREADY are all high. 
2) A completer that needs more time simply holds PREADY low in the Access phase
3) The requester keeps PENABLE high and holds every other signal steady until PREADY goes high (Use SVA)
4) PSLVERR is valid only in the last cycle of a transfer, when PSEL, PENABLE, and PREADY are all high (use SVA? if we have PSLVERR, check $past() of all)

Note: The requester never gives up -- APB has no timeout. A completer that never raises PREADY hangs the bus. 
So a slow completer must always finish.
*/