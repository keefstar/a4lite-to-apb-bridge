class axi_item extends uvm_sequence_item;
  //the item holds what happens in a transfer. the driver handles how the handhsake signals carry it.
  function new (string name = "axi_item");
    super.new(name);
  endfunction : new

  //declare AXI fields
  rand axi_transaction_kind kind;
  rand logic [AXI_DATA_WIDTH-1:0] data;
  rand logic [AXI_ADDR_WIDTH-1:0] addr;
  rand logic [AXI_PROT_WIDTH-1:0] prot;
  rand logic [AXI_STRB_WIDTH-1:0] strb;
  axi_resp_e resp;

  //control knobs
  //A sequence item holds WHAT a transfer carries (addr, data, strobe, resp),
  //never the handshake signals (VALID/READY/PENABLE) that decide WHEN it moves;
  //the driver generates those on the pins. Delay fields are just instructions
  //telling the driver how long to wait before a handshake, not the signals themselves.
  rand int unsigned arvalid_delay, awvalid_delay, wvalid_delay, bready_delay, rready_delay;
  rand int unsigned arready_delay, awready_delay, wready_delay, bvalid_delay, rvalid_delay;

  //constraints
  constraint data_c { (kind == AXI_READ) -> data == '0; }
  constraint strb_c { (kind == AXI_READ) -> strb == '0; }
  constraint addr_c { addr[1:0] == 2'b00; }

  constraint delay_c {
    //manager side
    soft arvalid_delay inside {[0:5]};
    soft awvalid_delay inside {[0:5]};
    soft wvalid_delay inside {[0:5]};
    soft bready_delay inside {[0:5]};
    soft rready_delay inside {[0:5]};
    //subordinate side
    soft arready_delay inside {[0:5]};
    soft awready_delay inside {[0:5]};
    soft wready_delay inside {[0:5]};
    soft bvalid_delay inside {[0:5]};
    soft rvalid_delay inside {[0:5]};
  }

  //uvm factory registration
  `uvm_object_utils_begin(axi_item)
    `uvm_field_enum(axi_transaction_kind, kind, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(prot, UVM_ALL_ON)
    `uvm_field_int(strb, UVM_ALL_ON)
    `uvm_field_enum(axi_resp_e, resp, UVM_ALL_ON)
    //use  UVM_NOCOMPARE for simulation knobs (actual axi item vs reconstructed item would have different delays and be flagged otherwise)
    `uvm_field_int(arvalid_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(awvalid_delay, UVM_ALL_ON | UVM_DEC| UVM_NOCOMPARE)
    `uvm_field_int(wvalid_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(bready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(rready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(arready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(awready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(wready_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(bvalid_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(rvalid_delay, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end
  
endclass : axi_item

