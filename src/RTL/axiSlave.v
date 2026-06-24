// =============================================================================
// AXI4 Slave RAM with FIXED-burst byte FIFO
//
//   - INCR / WRAP bursts  : memory-backed (unchanged behaviour)
//   - FIXED bursts        : routed to a separate byte-wide FIFO
//       * Write : for every strobed byte lane of each beat, the data byte is
//                 pushed into the FIFO (one FIFO element per byte). Narrow /
//                 unaligned / sparse transfers therefore push only as many
//                 entries as there are asserted wstrb bits.
//       * Read  : bytes are popped in pure FIFO order (oldest first), regardless
//                 of address, and placed on the byte lanes selected by araddr/
//                 arsize for that beat.
//   - FIFO full on write  -> SLVERR (overflowing bytes dropped)
//   - FIFO empty on read  -> SLVERR (missing bytes padded with 0)
//   - FIXED writes go to the FIFO ONLY (not mirrored into the RAM)
// =============================================================================

module axi_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12,
    parameter ID_WIDTH   = 4,
    parameter MEM_DEPTH  = 1024,
    parameter FIFO_DEPTH = 64        // number of bytes the FIXED FIFO can hold
)(
    // Global
    input  wire                     s_axi_aclk,
    input  wire                     s_axi_aresetn,
    // Write Address (AW)
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    // Write Data (W)
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    // Write Response (B)
    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    // Read Address (AR)
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
    // Read Data (R)
    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;
    localparam BURST_FIXED = 2'b00;
    localparam BURST_INCR  = 2'b01;
    localparam BURST_WRAP  = 2'b10;
    localparam STRB_WIDTH  = DATA_WIDTH / 8;
    localparam BYTE_BITS   = $clog2(STRB_WIDTH);
    localparam PTR_W       = $clog2(FIFO_DEPTH);

    // ------------------------------------------------------------------ memory
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------------- byte FIFO
    reg [7:0]        fifo_mem [0:FIFO_DEPTH-1];
    reg [PTR_W-1:0]  fifo_wr_ptr;
    reg [PTR_W-1:0]  fifo_rd_ptr;
    reg [PTR_W:0]    fifo_count;     // 0 .. FIFO_DEPTH

    // ---------------------------------------------------------------- helpers
    function [ADDR_WIDTH-1:0] wrap_mask;
        input [7:0] len; input [2:0] size;
        reg [ADDR_WIDTH-1:0] bytes;
        begin bytes = (len + 1) << size; wrap_mask = bytes - 1; end
    endfunction

    function [ADDR_WIDTH-1:0] next_addr;
        input [ADDR_WIDTH-1:0] addr; input [1:0] burst;
        input [2:0] size; input [ADDR_WIDTH-1:0] mask;
        begin
            case (burst)
                BURST_FIXED: next_addr = addr;
                BURST_INCR:  next_addr = addr + (1 << size);
                BURST_WRAP:  next_addr = (addr & ~mask) | ((addr + (1 << size)) & mask);
                default:     next_addr = addr + (1 << size);
            endcase
        end
    endfunction

    // number of active byte lanes for a beat (handles narrow/unaligned, clipped)
    function integer lane_count_f;
        input [ADDR_WIDTH-1:0] addr; input [2:0] size;
        integer s, off, lane, c;
        begin
            s = (1 << size); off = addr % STRB_WIDTH; c = 0;
            for (lane = 0; lane < STRB_WIDTH; lane = lane + 1)
                if (lane >= off && lane < off + s) c = c + 1;
            lane_count_f = c;
        end
    endfunction

    // number of asserted strobe bits
    function integer strb_count_f;
        input [STRB_WIDTH-1:0] strb;
        integer i, c;
        begin c = 0; for (i = 0; i < STRB_WIDTH; i = i + 1) c = c + strb[i]; strb_count_f = c; end
    endfunction

    // assemble a read beat from the FIFO (peek, no state change) for addr/size
    task fifo_assemble;
        input  [ADDR_WIDTH-1:0]  addr;
        input  [2:0]             size;
        output [DATA_WIDTH-1:0]  data_o;
        output                   underflow_o;
        integer s, off, lane, k, need;
        reg [STRB_WIDTH-1:0] mask;
        begin
            s = (1 << size); off = addr % STRB_WIDTH; mask = 0; need = 0;
            for (lane = 0; lane < STRB_WIDTH; lane = lane + 1)
                if (lane >= off && lane < off + s) begin mask[lane] = 1'b1; need = need + 1; end
            underflow_o = (need > fifo_count);
            data_o = {DATA_WIDTH{1'b0}};
            k = 0;
            for (lane = 0; lane < STRB_WIDTH; lane = lane + 1) begin
                if (mask[lane]) begin
                    if (k < fifo_count)
                        data_o[lane*8 +: 8] = fifo_mem[(fifo_rd_ptr + k) % FIFO_DEPTH];
                    k = k + 1;
                end
            end
        end
    endtask

    // =====================================================================
    //  WRITE FSM
    // =====================================================================
    localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;

    reg [1:0]            wr_state;
    reg [ID_WIDTH-1:0]   wr_id;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [7:0]            wr_len;
    reg [1:0]            wr_burst;
    reg [2:0]            wr_size;
    reg [ADDR_WIDTH-1:0] wr_wrap_mask;
    reg                  wr_err;        // sticky FIFO-overflow flag for FIXED

    wire [ADDR_WIDTH-1:0] wr_word_addr = wr_addr >> BYTE_BITS;

    // FIFO push request comes from an accepted FIXED write beat
    wire                  fifo_push_req = (wr_state == WR_DATA) && s_axi_wvalid &&
                                          s_axi_wready && (wr_burst == BURST_FIXED);
    wire [PTR_W:0]        fifo_space    = FIFO_DEPTH - fifo_count;
    wire [7:0]            fifo_push_need = fifo_push_req ? strb_count_f(s_axi_wstrb) : 8'd0;
    wire                  fifo_overflow  = fifo_push_req && (fifo_push_need > fifo_space);

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= RESP_OKAY;
            wr_err        <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    wr_err        <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id        <= s_axi_awid;
                        wr_addr      <= s_axi_awaddr;
                        wr_len       <= s_axi_awlen;
                        wr_burst     <= s_axi_awburst;
                        wr_size      <= s_axi_awsize;
                        wr_wrap_mask <= wrap_mask(s_axi_awlen, s_axi_awsize);
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Memory write only for non-FIXED bursts.
                        if (wr_burst != BURST_FIXED) begin
                            if (wr_word_addr < MEM_DEPTH) begin : byte_loop
                                integer b;
                                for (b = 0; b < STRB_WIDTH; b = b + 1)
                                    if (s_axi_wstrb[b])
                                        mem[wr_word_addr][b*8 +: 8] <= s_axi_wdata[b*8 +: 8];
                            end
                        end
                        // (FIXED push is handled in the FIFO control block.)
                        if (fifo_overflow) wr_err <= 1'b1;

                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bid    <= wr_id;
                            if (wr_burst == BURST_FIXED)
                                s_axi_bresp <= (wr_err || fifo_overflow) ? RESP_SLVERR : RESP_OKAY;
                            else
                                s_axi_bresp <= (wr_word_addr < MEM_DEPTH) ? RESP_OKAY : RESP_SLVERR;
                            wr_state <= WR_RESP;
                        end else begin
                            wr_addr <= next_addr(wr_addr, wr_burst, wr_size, wr_wrap_mask);
                            wr_len  <= wr_len - 1;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        wr_state      <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =====================================================================
    //  READ FSM
    // =====================================================================
    localparam RD_IDLE = 2'd0, RD_DATA = 2'd1;

    reg [1:0]            rd_state;
    reg [ID_WIDTH-1:0]   rd_id;
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg [7:0]            rd_len;
    reg [1:0]            rd_burst;
    reg [2:0]            rd_size;
    reg [ADDR_WIDTH-1:0] rd_wrap_mask;

    reg [ADDR_WIDTH-1:0] rd_nxt_addr;
    reg [ADDR_WIDTH-1:0] rd_word_sel;
    reg [DATA_WIDTH-1:0] fa_data;       // assembled FIFO read data
    reg                  fa_uf;         // FIFO underflow for this beat

    // FIFO pop requests from read beats
    wire rd_first_fixed = (rd_state == RD_IDLE) && s_axi_arvalid && s_axi_arready &&
                          (s_axi_arburst == BURST_FIXED);
    wire rd_next_fixed  = (rd_state == RD_DATA) && s_axi_rvalid && s_axi_rready &&
                          (rd_len != 8'd0) && (rd_burst == BURST_FIXED);
    wire        fifo_pop_req   = rd_first_fixed || rd_next_fixed;
    wire [7:0]  fifo_pop_count = rd_first_fixed ? lane_count_f(s_axi_araddr, s_axi_arsize) :
                                 rd_next_fixed  ? lane_count_f(rd_addr, rd_size) : 8'd0;

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

                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= s_axi_arid;
                        s_axi_rlast  <= (s_axi_arlen == 8'd0);

                        if (s_axi_arburst == BURST_FIXED) begin
                            fifo_assemble(s_axi_araddr, s_axi_arsize, fa_data, fa_uf);
                            s_axi_rdata <= fa_data;
                            s_axi_rresp <= fa_uf ? RESP_SLVERR : RESP_OKAY;
                        end else begin
                            rd_word_sel = s_axi_araddr >> BYTE_BITS;
                            if (rd_word_sel < MEM_DEPTH) begin
                                s_axi_rdata <= mem[rd_word_sel];
                                s_axi_rresp <= RESP_OKAY;
                            end else begin
                                s_axi_rdata <= {DATA_WIDTH{1'b0}};
                                s_axi_rresp <= RESP_SLVERR;
                            end
                        end

                        s_axi_arready <= 1'b0;
                        rd_state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (rd_len == 8'd0) begin
                            s_axi_rvalid  <= 1'b0;
                            s_axi_rlast   <= 1'b0;
                            s_axi_arready <= 1'b1;
                            rd_state      <= RD_IDLE;
                        end else begin
                            rd_nxt_addr = next_addr(rd_addr, rd_burst, rd_size, rd_wrap_mask);
                            rd_addr     <= rd_nxt_addr;
                            rd_len      <= rd_len - 1;
                            s_axi_rlast <= (rd_len == 8'd1);

                            if (rd_burst == BURST_FIXED) begin
                                fifo_assemble(rd_addr, rd_size, fa_data, fa_uf);
                                s_axi_rdata <= fa_data;
                                s_axi_rresp <= fa_uf ? RESP_SLVERR : RESP_OKAY;
                            end else begin
                                rd_word_sel = rd_nxt_addr >> BYTE_BITS;
                                if (rd_word_sel < MEM_DEPTH) begin
                                    s_axi_rdata <= mem[rd_word_sel];
                                    s_axi_rresp <= RESP_OKAY;
                                end else begin
                                    s_axi_rdata <= {DATA_WIDTH{1'b0}};
                                    s_axi_rresp <= RESP_SLVERR;
                                end
                            end
                        end
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // =====================================================================
    //  FIFO CONTROL  (single owner of fifo_mem / pointers / count)
    //    Resolves simultaneous push (FIXED write) and pop (FIXED read).
    // =====================================================================
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            fifo_wr_ptr <= {PTR_W{1'b0}};
            fifo_rd_ptr <= {PTR_W{1'b0}};
            fifo_count  <= {(PTR_W+1){1'b0}};
        end else begin : fifo_ctrl
            integer i, pushed, popped;
            integer wp;
            wp = fifo_wr_ptr;
            pushed = 0;
            // PUSH: strobed bytes of an accepted FIXED write beat
            if (fifo_push_req) begin
                for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                    if (s_axi_wstrb[i] && ((fifo_count + pushed) < FIFO_DEPTH)) begin
                        fifo_mem[wp % FIFO_DEPTH] <= s_axi_wdata[i*8 +: 8];
                        wp     = wp + 1;
                        pushed = pushed + 1;
                    end
                end
            end
            // POP: oldest bytes, clipped by occupancy (cannot pop fresh pushes)
            popped = 0;
            if (fifo_pop_req)
                popped = (fifo_pop_count <= fifo_count) ? fifo_pop_count : fifo_count;

            fifo_wr_ptr <= wp % FIFO_DEPTH;
            fifo_rd_ptr <= (fifo_rd_ptr + popped) % FIFO_DEPTH;
            fifo_count  <= fifo_count + pushed - popped;
        end
    end

endmodule
