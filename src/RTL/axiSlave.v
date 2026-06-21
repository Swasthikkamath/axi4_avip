module axi_ram #( parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12,
    parameter ID_WIDTH   = 4,
    parameter MEM_DEPTH  = 1024
)(
    // -------------------------------------------------------------------------
    // Global Signals
    // -------------------------------------------------------------------------
    input  wire                     s_axi_aclk,
    input  wire                     s_axi_aresetn,

    // -------------------------------------------------------------------------
    // Write Address Channel (AW)
    // -------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,    // Burst length (beats - 1)
    input  wire [2:0]               s_axi_awsize,   // Beat size (bytes per beat)
    input  wire [1:0]               s_axi_awburst,  // 00=FIXED, 01=INCR, 10=WRAP
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    // -------------------------------------------------------------------------
    // Write Data Channel (W)
    // -------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    // -------------------------------------------------------------------------
    // Write Response Channel (B)
    // -------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,   // 00=OKAY, 10=SLVERR
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    // -------------------------------------------------------------------------
    // Read Address Channel (AR)
    // -------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire [3:0]               s_axi_arregion,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    // -------------------------------------------------------------------------
    // Read Data Channel (R)
    // -------------------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,   // 00=OKAY, 10=SLVERR
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);

    // -------------------------------------------------------------------------
    // Local Parameters
    // -------------------------------------------------------------------------
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    localparam BURST_FIXED = 2'b00;
    localparam BURST_INCR  = 2'b01;
    localparam BURST_WRAP  = 2'b10;

    localparam STRB_WIDTH  = DATA_WIDTH / 8;
    localparam BYTE_BITS   = $clog2(STRB_WIDTH);  // Byte offset bits

    // awlen is 8 bits => maximum beats in a burst is 256
    localparam MAX_BEATS   = 256;

    // -------------------------------------------------------------------------
    // Internal Memory
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Loop indices used during the deferred memory commit
    integer ci, cb;

    // -------------------------------------------------------------------------
    // Write State Machine
    // -------------------------------------------------------------------------
    localparam WR_IDLE = 2'd0,
               WR_DATA = 2'd1,
               WR_RESP = 2'd2;

    reg [1:0]            wr_state;
    reg [ID_WIDTH-1:0]   wr_id;
    reg [ADDR_WIDTH-1:0] wr_addr;       // Current beat address
    reg [7:0]            wr_len;        // Remaining beats
    reg [1:0]            wr_burst;
    reg [2:0]            wr_size;
    reg [ADDR_WIDTH-1:0] wr_wrap_mask;  // Mask for WRAP burst boundary

    // -------------------------------------------------------------------------
    // Write-data staging buffers
    //
    // Beats are NOT written to memory as they arrive. They are collected here
    // during the WR_DATA phase, and the whole burst is committed to memory in
    // one shot when the write response is handed off to the master
    // (s_axi_bvalid && s_axi_bready) in WR_RESP.
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]  wbuf_data  [0:MAX_BEATS-1];
    reg [STRB_WIDTH-1:0]  wbuf_strb  [0:MAX_BEATS-1];
    reg [ADDR_WIDTH-1:0]  wbuf_waddr [0:MAX_BEATS-1];  // word address per beat
    reg [8:0]             wbuf_cnt;                    // beats staged (0..256)
    reg                   wr_err;                      // sticky out-of-range flag

    // Byte-aligned word address
    wire [ADDR_WIDTH-1:0] wr_word_addr = wr_addr >> BYTE_BITS;

    // WRAP boundary mask: (awlen+1) * (2^awsize) - 1
    function [ADDR_WIDTH-1:0] wrap_mask;
        input [7:0]  len;
        input [2:0]  size;
        reg   [ADDR_WIDTH-1:0] bytes;
        begin
            bytes     = (len + 1) << size;
            wrap_mask = bytes - 1;
        end
    endfunction

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= RESP_OKAY;
            wbuf_cnt      <= 9'd0;
            wr_err        <= 1'b0;
        end else begin
            case (wr_state)

                // ----------------------------------------------------------
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;

                    if (s_axi_awvalid && s_axi_awready) begin
                        // Latch write address channel info
                        wr_id         <= s_axi_awid;
                        wr_addr       <= s_axi_awaddr;
                        wr_len        <= s_axi_awlen;
                        wr_burst      <= s_axi_awburst;
                        wr_size       <= s_axi_awsize;
                        wr_wrap_mask  <= wrap_mask(s_axi_awlen, s_axi_awsize);

                        // Start a fresh staging buffer for this burst
                        wbuf_cnt      <= 9'd0;
                        wr_err        <= 1'b0;

                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                // ----------------------------------------------------------
                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Stage this beat (data + strobe + target word address).
                        // Nothing is written to memory yet.
                        wbuf_data [wbuf_cnt] <= s_axi_wdata;
                        wbuf_strb [wbuf_cnt] <= s_axi_wstrb;
                        wbuf_waddr[wbuf_cnt] <= wr_word_addr;
                        wbuf_cnt             <= wbuf_cnt + 1'b1;

                        // Sticky error if any beat targets outside memory
                        if (wr_word_addr >= MEM_DEPTH)
                            wr_err <= 1'b1;

                        if (s_axi_wlast) begin
                            // Last beat staged -> present the response.
                            // Memory is updated later, at the B handshake.
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bid    <= wr_id;
                            // wr_err is non-blocking, so OR in this beat's check
                            s_axi_bresp  <= (wr_err || (wr_word_addr >= MEM_DEPTH))
                                                ? RESP_SLVERR : RESP_OKAY;
                            wr_state     <= WR_RESP;
                        end else begin
                            // Advance address for next beat
                            case (wr_burst)
                                BURST_FIXED: ; // Address stays the same
                                BURST_INCR:  wr_addr <= wr_addr + (1 << wr_size);
                                BURST_WRAP: begin
                                    // Increment within the wrap boundary
                                    wr_addr <= (wr_addr & ~wr_wrap_mask) |
                                               ((wr_addr + (1 << wr_size)) & wr_wrap_mask);
                                end
                                default: wr_addr <= wr_addr + (1 << wr_size);
                            endcase
                            wr_len <= wr_len - 1;
                        end
                    end
                end

                // ----------------------------------------------------------
                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        // ----------------------------------------------------
                        // Commit the whole burst to memory at response time.
                        // Each staged beat performs its byte-enabled write now.
                        // ----------------------------------------------------
                        for (ci = 0; ci < MAX_BEATS; ci = ci + 1) begin
                            if (ci < wbuf_cnt && wbuf_waddr[ci] < MEM_DEPTH) begin
                                for (cb = 0; cb < STRB_WIDTH; cb = cb + 1) begin
                                    if (wbuf_strb[ci][cb])
                                        mem[wbuf_waddr[ci]][cb*8 +: 8] <=
                                            wbuf_data[ci][cb*8 +: 8];
                                end
                            end
                        end

                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;  // Ready for next transaction
                        wbuf_cnt      <= 9'd0;
                        wr_state      <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Read State Machine
    // -------------------------------------------------------------------------
    localparam RD_IDLE = 2'd0,
               RD_DATA = 2'd1;

    reg [1:0]            rd_state;
    reg [ID_WIDTH-1:0]   rd_id;
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg [7:0]            rd_len;        // Remaining beats (counts down)
    reg [1:0]            rd_burst;
    reg [2:0]            rd_size;
    reg [ADDR_WIDTH-1:0] rd_wrap_mask;

    // Combinational next-beat address for a burst
    function [ADDR_WIDTH-1:0] next_addr;
        input [ADDR_WIDTH-1:0] addr;
        input [1:0]            burst;
        input [2:0]            size;
        input [ADDR_WIDTH-1:0] mask;
        begin
            case (burst)
                BURST_FIXED: next_addr = addr;
                BURST_INCR:  next_addr = addr + (1 << size);
                BURST_WRAP:  next_addr = (addr & ~mask) |
                                         ((addr + (1 << size)) & mask);
                default:     next_addr = addr + (1 << size);
            endcase
        end
    endfunction

    // Helper: load one beat of read data from memory at the given address
    // (combinational selection of word; registered assignment happens at call site)
    reg [ADDR_WIDTH-1:0] rd_nxt_addr;
    reg [ADDR_WIDTH-1:0] rd_word_sel;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
        end else begin
            case (rd_state)

                // ----------------------------------------------------------
                RD_IDLE: begin
                    s_axi_arready <= 1'b1;
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;

                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id        <= s_axi_arid;
                        rd_addr      <= s_axi_araddr;
                        rd_len       <= s_axi_arlen;
                        rd_burst     <= s_axi_arburst;
                        rd_size      <= s_axi_arsize;
                        rd_wrap_mask <= wrap_mask(s_axi_arlen, s_axi_arsize);

                        // Load the FIRST beat immediately
                        rd_word_sel   = s_axi_araddr >> BYTE_BITS;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rid     <= s_axi_arid;
                        s_axi_rlast   <= (s_axi_arlen == 8'd0);  // single-beat burst
                        if (rd_word_sel < MEM_DEPTH) begin
                            s_axi_rdata <= mem[rd_word_sel];
                            s_axi_rresp <= RESP_OKAY;
                        end else begin
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                            s_axi_rresp <= RESP_SLVERR;
                        end

                        s_axi_arready <= 1'b0;
                        rd_state      <= RD_DATA;
                    end
                end

                // ----------------------------------------------------------
                RD_DATA: begin
                    // rvalid/rdata/rlast are held stable until the current
                    // beat is accepted (rvalid && rready).
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (rd_len == 8'd0) begin
                            // Final beat just accepted  close out
                            s_axi_rvalid  <= 1'b0;
                            s_axi_rlast   <= 1'b0;
                            s_axi_arready <= 1'b1;
                            rd_state      <= RD_IDLE;
                        end else begin
                            // Advance and load the NEXT beat
                            rd_nxt_addr = next_addr(rd_addr, rd_burst,
                                                    rd_size, rd_wrap_mask);
                            rd_word_sel = rd_nxt_addr >> BYTE_BITS;

                            rd_addr     <= rd_nxt_addr;
                            rd_len      <= rd_len - 1;
                            s_axi_rlast <= (rd_len == 8'd1);  // next beat is last

                            if (rd_word_sel < MEM_DEPTH) begin
                                s_axi_rdata <= mem[rd_word_sel];
                                s_axi_rresp <= RESP_OKAY;
                            end else begin
                                s_axi_rdata <= {DATA_WIDTH{1'b0}};
                                s_axi_rresp <= RESP_SLVERR;
                            end
                            // rvalid stays asserted
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
