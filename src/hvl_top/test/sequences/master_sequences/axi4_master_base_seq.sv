`ifndef AXI4_MASTER_BASE_SEQ_INCLUDED_
`define AXI4_MASTER_BASE_SEQ_INCLUDED_

//--------------------------------------------------------------------------------------------
// Class: axi4_master_base_seq 
// creating axi4_master_base_seq class extends from uvm_sequence
//--------------------------------------------------------------------------------------------
class axi4_master_base_seq extends uvm_sequence #(axi4_master_tx);

  //factory registration
  `uvm_object_utils(axi4_master_base_seq)
  
  awsize_e tranSize;

  transfer_type_e transferType;
  
  awburst_e burstType;
  
  tx_type_e writeOrRead;
  //-------------------------------------------------------
  // Externally defined Function
  //-------------------------------------------------------
  extern function new(string name = "axi4_master_base_seq");
  extern task body();
endclass : axi4_master_base_seq

//-----------------------------------------------------------------------------
// Constructor: new
// Initializes the axi4_master_sequence class object
//
// Parameters:
//  name - instance name of the config_template
//-----------------------------------------------------------------------------
function axi4_master_base_seq::new(string name = "axi4_master_base_seq");
  super.new(name);
endfunction : new

//-----------------------------------------------------------------------------
// Task: body
// based on the request from driver task will drive the transactions
task axi4_master_base_seq::body();
  super.body();
  `uvm_info(get_type_name(), $sformatf("Generating %s transaction | size=%s burst=%s type=%s",
            writeOrRead.name(), tranSize.name(), burstType.name(), transferType.name()), UVM_LOW)

  req = axi4_master_tx::type_id::create("req");

  start_item(req);
  if(!req.randomize() with {req.awsize == tranSize;
                              req.tx_type == writeOrRead;
                              req.transfer_type == transferType;
                              req.awburst == burstType;}) begin
    `uvm_fatal(get_type_name(), $sformatf("Randomization failed for axi4_master_tx (size=%s burst=%s type=%s)",
               tranSize.name(), burstType.name(), transferType.name()))
  end

  `uvm_info(get_type_name(), $sformatf("Randomized transaction:\n%s", req.sprint()), UVM_HIGH)

  finish_item(req);
  `uvm_info(get_type_name(), $sformatf("%s transaction sent to driver", writeOrRead.name()), UVM_MEDIUM)

endtask : body


`endif
