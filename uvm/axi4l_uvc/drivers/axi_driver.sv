class axi_driver extends uvm_driver #(axi_item);

  `uvm_component_utils(uvm_driver)

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  //obtain virtual interface
  virtual a4lite_if a4l_if;
  
  virtual function build_phase (uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual a4lite_if)::get(this, "", "a4l_if", a4l_if))
      `uvm_fatal(get_type_name(), $sformatf("Cannot obtain virtual interface for upstream AXI4-Lite"))
  endfunction 

  virtual task run_phase (uvm_phase phase);
    //
  endtask : run_phase


endclass : axi_driver