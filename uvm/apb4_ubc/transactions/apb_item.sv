class apb_item extends uvm_sequence_item;

  function new (string name = "apb_item");
    super.new(name);
  endfunction : new

  //requester fields
  rand logic pwrite;
  rand logic [APB_STRB_WIDTH-1:0] pstrb;
  rand logic [APB_DATA_WIDTH-1:0] pwdata;
  rand logic [APB_PROT_WIDTH-1:0] pprot;
  rand logic [APB_ADDR_WIDTH-1:0] paddr;

    //completer fields
  rand logic pslverr;
  rand logic [APB_DATA_WIDTH-1:0] prdata;
  constraint pslverr_c { soft pslverr == 0; }

  //constraints
  constraint pwdata_c {(pwrite == 0) -> pwdata == '0;}
  constraint pstrb_c {(pwrite == 0) -> pstrb == '0; }

  //control knobs
  rand int unsigned pready_delay;
  rand int unsigned idle_cycles;
  constraint delay_c {
    soft idle_cycles inside {[0:5]};
    soft pready_delay inside {[0:5]};
  }

  `uvm_object_utils_begin(apb_item)
    `uvm_field_int(pwrite, UVM_ALL_ON)
    `uvm_field_int(pwdata, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(prdata, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(paddr, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(pstrb, UVM_ALL_ON)
    `uvm_field_int(pprot, UVM_ALL_ON)
    `uvm_field_int(pslverr, UVM_ALL_ON)
  //
    `uvm_field_int(pready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(idle_cycles, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

endclass : apb_item