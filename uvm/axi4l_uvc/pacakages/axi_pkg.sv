package axi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int AXI_ADDR_WIDTH = 32;
    parameter int AXI_DATA_WIDTH = 32;
    parameter int AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8);
    parameter int AXI_PROT_WIDTH = 3;

    typedef enum logic {
      AXI_READ, 
      AXI_WRITE
    } axi_transaction_kind;

    typedef enum logic [1:0] {
      AXI_OKAY = 2'b00,
      AXI_EXOKAY = 2'b01, //unsupported in AXI4-Lite
      AXI_SLVERR = 2'b10,
      AXI_DECERR = 2'b11
    } axi_resp_e;

    //for use by agent to declare AXI manager or subordinate
    typedef enum logic {
      AXI_MANAGER, 
      AXI_SUBORDINATE
    } axi_role_e;

    `include "axi_item.sv"


endpackage : axi_pkg