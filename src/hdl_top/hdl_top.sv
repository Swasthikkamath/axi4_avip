`ifndef HDL_TOP_INCLUDED_
`define HDL_TOP_INCLUDED_

//--------------------------------------------------------------------------------------------
// Module      : HDL Top
// Description : Has a interface master and slave agent bfm.
//--------------------------------------------------------------------------------------------

module hdl_top;

  import uvm_pkg::*;
  import axi4_globals_pkg::*;
  `include "uvm_macros.svh"

  //-------------------------------------------------------
  // Clock Reset Initialization
  //-------------------------------------------------------
  bit aclk;
  bit aresetn;

  //-------------------------------------------------------
  // System Clock Generation
  //-------------------------------------------------------
  initial begin
    aclk = 1'b0;
    forever #10 aclk = ~aclk;
  end

  //-------------------------------------------------------
  // System Reset Generation
  // Active low reset
  //-------------------------------------------------------
  initial begin
    aresetn = 1'b1;
    #10 aresetn = 1'b0;

    repeat (1) begin
      @(posedge aclk);
    end
    aresetn = 1'b1;
  end
  
  initial begin
    $dumpfile("waveform.vcd");      // name of the VCD file
    $dumpvars(0, hdl_top);    // dump variables from the testbench top
  end

  // Variable : intf
  // axi4 Interface Instantiation
  axi4_if intf(.aclk(aclk),
               .aresetn(aresetn));


 axi_ram #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDRESS_WIDTH),
    .ID_WIDTH   (4)
 ) slave (
    // Global
    .s_axi_aclk    (aclk),
    .s_axi_aresetn    (aresetn),

    // Write Address Channel
    .s_axi_awid     (intf.awid),
    .s_axi_awaddr   (intf.awaddr),
    .s_axi_awlen    (intf.awlen),
    .s_axi_awsize   (intf.awsize),
    .s_axi_awburst  (intf.awburst),
    .s_axi_awlock   (intf.awlock),
    .s_axi_awcache  (intf.awcache),
    .s_axi_awprot   (intf.awprot),
    .s_axi_awvalid  (intf.awvalid),
    .s_axi_awready  (intf.awready),

    // Write Data Channel
    .s_axi_wdata    (intf.wdata),
    .s_axi_wstrb    (intf.wstrb),
    .s_axi_wlast    (intf.wlast),
    .s_axi_wvalid   (intf.wvalid),
    .s_axi_wready   (intf.wready),

    // Write Response Channel
    .s_axi_bid      (intf.bid),
    .s_axi_bresp    (intf.bresp),
    .s_axi_bvalid   (intf.bvalid),
    .s_axi_bready   (intf.bready),

    // Read Address Channel
    .s_axi_arid     (intf.arid),
    .s_axi_araddr   (intf.araddr),
    .s_axi_arlen    (intf.arlen),
    .s_axi_arsize   (intf.arsize),
    .s_axi_arburst  (intf.arburst),
    .s_axi_arlock   (intf.arlock),
    .s_axi_arcache  (intf.arcache),
    .s_axi_arprot   (intf.arprot),
    .s_axi_arvalid  (intf.arvalid),
    .s_axi_arready  (intf.arready),

    // Read Data Channel
    .s_axi_rid      (intf.rid),
    .s_axi_rdata    (intf.rdata),
    .s_axi_rresp    (intf.rresp),
    .s_axi_rlast    (intf.rlast),
    .s_axi_rvalid   (intf.rvalid),
    .s_axi_rready   (intf.rready)
);  

  // AXI4  No of Master and Slaves Agent Instantiation
  //-------------------------------------------------------
  genvar i;
  generate
  
    for (i=0; i<NO_OF_MASTERS; i++) begin : axi4_master_agent_bfm
      axi4_master_agent_bfm #(.MASTER_ID(i)) axi4_master_agent_bfm_h(intf);
      defparam axi4_master_agent_bfm[i].axi4_master_agent_bfm_h.MASTER_ID = i;
    end
  

    for (i=0; i<NO_OF_SLAVES; i++) begin : axi4_slave_agent_bfm
      axi4_slave_agent_bfm #(.SLAVE_ID(i)) axi4_slave_agent_bfm_h(intf);
      defparam axi4_slave_agent_bfm[i].axi4_slave_agent_bfm_h.SLAVE_ID = i;
    end
  endgenerate
 

endmodule : hdl_top

`endif

