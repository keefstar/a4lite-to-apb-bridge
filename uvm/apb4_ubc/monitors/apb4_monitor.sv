class apb4_monitor extends uvm_monitor;

  `uvm_component_utils(apb4_monitor)

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  virtual apb4_if apb_if; //declare virtual handle for APB interface
  uvm_analysis_port#(apb_item) mon_analysis_port;

  virtual function void build_phase (uvm_phase phase);
    super.build_phase(phase);
    mon_analysis_port = new("mon_analysis_port", this);
    if (!uvm_config_db#(virtual apb4_if)::get(this, "", "apb_if", apb_if))
      `uvm_error(get_type_name(), $sformatf("Could not obtain virtual interface for APB"))
  endfunction : build_phase

  //reconstruct transaction
  virtual task run_phase (uvm_phase phase);
    apb_item tr;
    forever begin
      @(apb_if.apb4_mon_cb);
      //transfer is complete when PSEL && PENABLE && PREADY == 1
      if ((|apb_if.apb4_mon_cb.PSEL && apb_if.apb4_mon_cb.PENABLE && apb_if.apb4_mon_cb.PREADY) && (apb_if.PRESETn)) begin
        tr = apb_item::type_id::create("tr", this);
        tr.pwrite = apb_if.apb4_mon_cb.PWRITE;
        tr.pprot = apb_if.apb4_mon_cb.PPROT;
        tr.paddr = apb_if.apb4_mon_cb.PADDR;
        tr.pstrb = apb_if.apb4_mon_cb.PSTRB;
        if (!tr.pwrite) tr.prdata = apb_if.apb4_mon_cb.PRDATA;
        else tr.pwdata = apb_if.apb4_mon_cb.PWDATA;
        tr.pslverr = apb_if.apb4_mon_cb.PSLVERR;
        mon_analysis_port.write(tr);
      end
    end
  endtask : run_phase

endclass : apb4_monitor