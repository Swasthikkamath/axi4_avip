`ifndef AXI4_IF_INCLUDED_
`define AXI4_IF_INCLUDED_

// Import axi4_globals_pkg 
import axi4_globals_pkg::*;

//--------------------------------------------------------------------------------------------
// Interface : axi4_if
// Declaration of pin level signals for axi4 interface
//--------------------------------------------------------------------------------------------
interface axi4_if(input aclk, input aresetn);

  //Write_address_channel
  wire logic     [3: 0] awid     ;
  wire logic     [ADDRESS_WIDTH-1: 0] awaddr ;
  wire logic     [7: 0] awlen     ;
  wire logic     [2: 0] awsize    ;
  wire logic     [1: 0] awburst   ;
  wire logic     [1: 0] awlock    ;
  wire logic     [3: 0] awcache   ;
  wire logic     [2: 0] awprot    ;
  wire logic     [3:0] awqos      ;
  wire  logic     [3:0] awregion   ;
  wire logic           awuser     ;
  wire logic            awvalid   ;
  wire logic           awready   ;
  //Write_data_channel
  wire logic     [DATA_WIDTH-1: 0] wdata     ;
  wire logic     [(DATA_WIDTH/8)-1: 0] wstrb ;
  wire logic            wlast     ;
  wire logic      [3:0] wuser     ;
  wire logic            wvalid    ;
  wire logic            wready    ;
  //Write Response Channel
  wire logic     [3: 0] bid       ;
  wire logic     [1: 0] bresp     ;
  wire logic     [3: 0] buser     ;
  wire logic            bvalid    ;
  wire logic            bready    ;
  //Read Address Channel
  wire logic     [3: 0] arid     ;
  wire logic     [ADDRESS_WIDTH-1:0] araddr  ;
  wire logic     [7:0] arlen      ;
  wire logic     [2:0] arsize     ;
  wire logic     [1:0] arburst    ;
  wire logic     [1:0] arlock     ;
  wire logic     [3:0] arcache    ;
  wire logic     [2:0] arprot     ;
  wire logic     [3:0] arqos      ;
  wire logic     [3:0] arregion   ;
  wire logic     [3:0] aruser     ;
  wire logic           arvalid    ;
  wire logic           arready    ;
  //Read Data Channel
  wire logic     [3: 0] rid      ;
  wire logic     [DATA_WIDTH-1: 0] rdata     ;
  wire logic     [1:0] rresp      ;
  wire logic           rlast      ;
  wire logic     [3:0] ruser      ;
  wire logic           rvalid     ;
  wire logic           rready     ;
  

endinterface: axi4_if 

`endif
