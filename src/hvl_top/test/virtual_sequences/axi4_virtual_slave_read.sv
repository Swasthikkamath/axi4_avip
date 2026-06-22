`ifndef AXI4_VIRTUAL_SLAVE_READ_SEQ_INCLUDED_
`define AXI4_VIRTUAL_SLAVE_READ_SEQ_INCLUDED_

//--------------------------------------------------------------------------------------------
// Class: axi4_virtual__slave_read
// Creates and starts the slave and slave sequences
//--------------------------------------------------------------------------------------------
class axi4_virtual_slave_read extends axi4_virtual_base_seq;
  `uvm_object_utils(axi4_virtual__slave_read)

  //Variable: axi4_slave_read_seq_h
  //Instantiation of axi4_slave_read_seq handle
  axi4_slave_base_seq axi4_slave_read_seq_h;


  int readAccepted;
  //-------------------------------------------------------
  // Externally defined Tasks and Functions
  //-------------------------------------------------------
  extern function new(string name = "axi4_virtual__slave_read");
  extern task body();
endclass : axi4_virtual__slave_read

//--------------------------------------------------------------------------------------------
// Construct: new
// Initialises new memory for the object
//
// Parameters:
//  name - axi4_virtual__slave_read
//--------------------------------------------------------------------------------------------
function axi4_virtual_slave_read::new(string name = "axi4_virtual__slave_read");
  super.new(name);
endfunction : new

//--------------------------------------------------------------------------------------------
// Task - body
// Creates and starts the data of slave and slave sequences
//--------------------------------------------------------------------------------------------
task axi4_virtual_slave_read::body();
  axi4_slave_read_seq_h = axi4_slave_base_seq::type_id::create("axi4_slave_read_seq_h");

  axi4_slave_read_seq_h.readTransferType = readTransferType;
  axi4_slave_read_seq_h.readOrRead  = READ;
  `uvm_info(get_type_name(), $sformatf("Starting READ virtual sequence | size=%s burst=%s type=%s",
            readTranSize.name(), readBurstType.name(), readTransferType.name()), UVM_LOW)
  fork
    begin: T1_READ
      repeat(MASTER_TRANSACTION_READ_ISSUE_COUNT) begin
        axi4_slave_read_seq_h.start(p_sequencer.axi4_slave_read_seqr_h);
      end
    end
  join
  
 endtask : body

`endif

