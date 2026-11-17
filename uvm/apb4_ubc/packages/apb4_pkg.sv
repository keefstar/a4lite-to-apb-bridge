package apb4_pkg;
    import uvm_pkg::*;
  `include "uvm_macros.svh"

    parameter int APB_ADDR_WIDTH = 32;
    parameter int APB_DATA_WIDTH = 32;
    parameter int APB_STRB_WIDTH = (APB_DATA_WIDTH/8);
    parameter int APB_PROT_WIDTH = 3;

    //for agent
    typedef enum logic {
      APB_COMPLETER,
      APB_REQUESTER
    } apb4_role_e;

    `include "apb_item.sv"

endpackage : apb4_pkg