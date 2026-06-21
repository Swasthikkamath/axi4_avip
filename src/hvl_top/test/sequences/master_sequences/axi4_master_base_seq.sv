`ifndef AXI4_MASTER_BASE_SEQ_INCLUDED_
`define AXI4_MASTER_BASE_SEQ_INCLUDED_

//--------------------------------------------------------------------------------------------
// Class: axi4_master_base_seq 
// creating axi4_master_base_seq class extends from uvm_sequence
//--------------------------------------------------------------------------------------------
class axi4_master_base_seq extends uvm_sequence #(axi4_master_tx);

  //factory registration
  `uvm_object_utils(axi4_master_base_seq)
  
  awsize_e writeTranSize;

  transfer_type_e writeTransferType;
  
  awburst_e writeBurstType;
  
  tx_type_e writeOrRead;

   arsize_e readTranSize;

  transfer_type_e readTransferType;
  
  arburst_e readBurstType;
  



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
    `uvm_info(get_type_name(), $sformatf("DEBUG_MSHA :: BEFORE axi4_master_bk_write_32b_transfer_seq"), UVM_NONE); 

  req = axi4_master_tx::type_id::create("req");
  
  start_item(req);
  if(writeOrRead == WRITE) begin
    if(!req.randomize() with {req.awsize == writeTranSize;
                              req.tx_type == writeOrRead;
                              req.transfer_type == writeTransferType;
                              req.awburst == writeBurstType;}) begin
    
      `uvm_fatal("axi4","Rand failed");
    end
  end
  else begin 
   if(!req.randomize() with {req.arsize == readTranSize;
                              req.tx_type == writeOrRead;
                              req.transfer_type == readTransferType;
                              req.arburst == readBurstType;}) begin
    
      `uvm_fatal("axi4","Rand failed");
    end
     

  end 
  
  `uvm_info(get_type_name(), $sformatf("master_seq \n%s",req.sprint()), UVM_NONE); 
  
  finish_item(req);
  `uvm_info(get_type_name(), $sformatf("DEBUG_MSHA :: AFTER axi4_master_bk_write_32b_transfer_seq"), UVM_NONE); 

endtask : body


`endif
