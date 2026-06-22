`ifndef AXI4_VIRTUAL_SLAVE_WRITE_INCLUDED_
`define AXI4_VIRTUAL_SLAVE_WRITE_INCLUDED_

//--------------------------------------------------------------------------------------------
// Class: axi4_virtual__slave_write
// Creates and starts the slave and slave sequences
//--------------------------------------------------------------------------------------------
class axi4_virtual_slave_write extends axi4_virtual_base_seq;
  `uvm_object_utils(axi4_virtual__slave_write)

  //Variable: axi4_slave_write_seq_h
  //Instantiation of axi4_slave_write_seq handle
  axi4_slave_base_seq axi4_slave_write_seq_h;


  int writeAccepted;
  //-------------------------------------------------------
  // Externally defined Tasks and Functions
  //-------------------------------------------------------
  extern function new(string name = "axi4_virtual__slave_write");
  extern task body();
endclass : axi4_virtual__slave_write

//--------------------------------------------------------------------------------------------
// Construct: new
// Initialises new memory for the object
//
// Parameters:
//  name - axi4_virtual__slave_write
//--------------------------------------------------------------------------------------------
function axi4_virtual_slave_write::new(string name = "axi4_virtual__slave_write");
  super.new(name);
endfunction : new

//--------------------------------------------------------------------------------------------
// Task - body
// Creates and starts the data of slave and slave sequences
//--------------------------------------------------------------------------------------------
task axi4_virtual_slave_write::body();
  axi4_slave_write_seq_h = axi4_slave_base_seq::type_id::create("axi4_slave_write_seq_h");

  axi4_slave_write_seq_h.writeTransferType = writeTransferType;
  axi4_slave_write_seq_h.writeOrRead  = WRITE;
  `uvm_info(get_type_name(), $sformatf("Starting WRITE virtual sequence | size=%s burst=%s type=%s",
            writeTranSize.name(), writeBurstType.name(), writeTransferType.name()), UVM_LOW)
  fork
    begin: T1_WRITE
        axi4_slave_write_seq_h.start(p_sequencer.axi4_slave_write_seqr_h);
    end
  join
  
 endtask : body

`endif

