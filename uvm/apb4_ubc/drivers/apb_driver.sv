class apb_driver extends uvm_driver # (apb_item);

  `uvm_component_utils(apb_driver)
  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  virtual apb4_if apb_if;
  apb4_role_e role;
  virtual function void build_phase (uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb4_if)::get(this, "", "apb_if", apb_if)) 
      `uvm_fatal(get_type_name(), $sformatf("Failed to obtain virtual handle to APB interface"))
    if (!uvm_config_db#(apb4_role_e)::get(this, "", "role", role))
      `uvm_fatal(get_type_name(), $sformatf("Failed to determine whether APB agent is a requester or completer"))
  endfunction : build_phase

  virtual task run_phase (uvm_phase phase);
     @ (apb_if.apb4_drv_req_cb); //place driver on edge.
    forever begin
      if (role == APB_REQUESTER) run_requester();
      else run_completer();
    end
  endtask : run_phase

  task run_requester();
    apb_item tr;
    seq_item_port.get_next_item(tr);
    repeat (tr.idle_cycles)  @(apb_if.apb4_drv_req_cb);
    //signals sampled by DUT
    apb_if.apb4_drv_req_cb.PENABLE <= 1'b0;
    apb_if.apb4_drv_req_cb.PADDR <= tr.paddr;
    apb_if.apb4_drv_req_cb.PWRITE <= tr.pwrite;
    apb_if.apb4_drv_req_cb.PWDATA <= tr.pwdata;
    apb_if.apb4_drv_req_cb.PSTRB <= tr.pstrb;
    apb_if.apb4_drv_req_cb.PPROT <= tr.pprot;
    //assert PSEL to move from IDLE to SETUP (one cycle).
    apb_if.apb4_drv_req_cb.PSEL <= 1'b1;
    @(apb_if.apb4_drv_req_cb);
    //assert PENABLE in ACCESS state.
    apb_if.apb4_drv_req_cb.PENABLE <= 1'b1;
    //PREADY counts only at the edge whre PSEL and PENABLE are both high. PREADY being high during setup or idle means nothing
    do begin
      @(apb_if.apb4_drv_req_cb);
    end while (!apb_if.apb4_drv_req_cb.PREADY);
    //drop PSEL and PENABLE. capture signals from DUT.
    apb_if.apb4_drv_req_cb.PSEL <= 1'b0;
    apb_if.apb4_drv_req_cb.PENABLE <= 1'b0;
    tr.pslverr = apb_if.apb4_drv_req_cb.PSLVERR;
    if (!tr.pwrite) tr.prdata = apb_if.apb4_drv_req_cb.PRDATA;
    seq_item_port.item_done();
  endtask : run_requester

  task run_completer();
    apb_item tr;
    while (!(apb_if.apb4_drv_com_cb.PSEL && !apb_if.apb4_drv_com_cb.PENABLE)) @ (apb_if.apb4_drv_com_cb); //mark SETUP phase entry.
    seq_item_port.get_next_item(tr);
    if (!apb_if.apb4_drv_com_cb.PWRITE) apb_if.apb4_drv_com_cb.PRDATA <= tr.prdata;
    repeat (tr.pready_delay) @ (apb_if.apb4_drv_com_cb);
    apb_if.apb4_drv_com_cb.PREADY <= 1'b1;
    apb_if.apb4_drv_com_cb.PSLVERR <= tr.pslverr;
    @ (apb_if.apb4_drv_com_cb);
    apb_if.apb4_drv_com_cb.PREADY <= 1'b0;
    apb_if.apb4_drv_com_cb.PSLVERR <= '0;
    seq_item_port.item_done();
  endtask : run_completer

endclass : apb_driver
/*

completer logic:
When requester asserts PSEL, that marks the SETUP phase (PADDR, PWRITE, and PWDATA are valid on that cycle). PENABLE must also be low here.
This lasts one cycle (move to ACCESS right away). Now, call get_next_item().
For completer sequence, the item is the response planf or the transfer.  it tells the driver shit like pready_delay, pslverr, and prdata (is read).
Once PREADY is raised. Deassert it next cycle (there is no APB requester backpressure).
Then item_done 
Then repeat.

requester logic:
get_next_item() comes first. '
apb_item zero out PWDATA and PSTRB on reads, so driver can drive every field the same way without much branching.
can deal with idle_cycles latency.
SETUP is reached when PSEL is asserted, and drive PADDR, PWRITE, PWDATA, PSTRB, PPROT, with PENABLE = 0. This lasts one cycle.
IN ACCESS, hold all metadata signals stable, and assert PENABLE = 1.
Upon PREADY, capture pslverr and prdata (if read).
Drop PSEL and PENABLE (unless another transfer starts back-to-back), then item_done()
*/