module axi_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12,
    parameter ID_WIDTH   = 4,
    parameter MEM_DEPTH  = 1024,
    parameter FIFO_DEPTH = 64
)(
    input  wire                     s_axi_aclk,
    input  wire                     s_axi_aresetn,
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
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
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

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // ---- byte FIFO (committed data) ----
    reg [7:0]        fifo_mem [0:FIFO_DEPTH-1];
    reg [PTR_W-1:0]  fifo_wr_ptr;
    reg [PTR_W-1:0]  fifo_rd_ptr;
    reg [PTR_W:0]    fifo_count;

    // ---- staging buffer (uncommitted FIXED-write bytes) ----
    reg [7:0]        stg_mem [0:FIFO_DEPTH-1];
    reg [PTR_W:0]    stg_store;   // bytes currently staged (0..FIFO_DEPTH)
    reg              stg_ovf;     // staging exceeded FIFO capacity

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

    function integer strb_count_f;
        input [STRB_WIDTH-1:0] strb;
        integer i, c;
        begin c = 0; for (i = 0; i < STRB_WIDTH; i = i + 1) c = c + strb[i]; strb_count_f = c; end
    endfunction

    task fifo_assemble;                 // peek a read beat from committed FIFO
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

    wire [ADDR_WIDTH-1:0] wr_word_addr = wr_addr >> BYTE_BITS;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            s_axi_bresp   <= RESP_OKAY;
            stg_store     <= {(PTR_W+1){1'b0}};
            stg_ovf       <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id        <= s_axi_awid;
                        wr_addr      <= s_axi_awaddr;
                        wr_len       <= s_axi_awlen;
                        wr_burst     <= s_axi_awburst;
                        wr_size      <= s_axi_awsize;
                        wr_wrap_mask <= wrap_mask(s_axi_awlen, s_axi_awsize);
                        stg_store    <= {(PTR_W+1){1'b0}};   // fresh staging
                        stg_ovf      <= 1'b0;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (wr_burst != BURST_FIXED) begin
                            // INCR/WRAP -> memory, per beat
                            if (wr_word_addr < MEM_DEPTH) begin : byte_loop
                                integer b;
                                for (b = 0; b < STRB_WIDTH; b = b + 1)
                                    if (s_axi_wstrb[b])
                                        mem[wr_word_addr][b*8 +: 8] <= s_axi_wdata[b*8 +: 8];
                            end
                        end else begin : stage_loop
                            // FIXED -> stage strobed bytes (not yet in FIFO)
                            integer b, sc; reg ovf;
                            sc = stg_store; ovf = stg_ovf;
                            for (b = 0; b < STRB_WIDTH; b = b + 1) begin
                                if (s_axi_wstrb[b]) begin
                                    if (sc < FIFO_DEPTH) begin
                                        stg_mem[sc] <= s_axi_wdata[b*8 +: 8];
                                        sc = sc + 1;
                                    end else ovf = 1'b1;
                                end
                            end
                            stg_store <= sc;
                            stg_ovf   <= ovf;
                        end

                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bid    <= wr_id;
                            if (wr_burst == BURST_FIXED) begin
                                // total staged = prior + this beat's strobed bytes
                                if (stg_ovf ||
                                    ((stg_store + strb_count_f(s_axi_wstrb)) >
                                     (FIFO_DEPTH - fifo_count)))
                                    s_axi_bresp <= RESP_SLVERR;
                                else
                                    s_axi_bresp <= RESP_OKAY;
                            end else begin
                                s_axi_bresp <= (wr_word_addr < MEM_DEPTH) ? RESP_OKAY : RESP_SLVERR;
                            end
                            wr_state <= WR_RESP;
                        end else begin
                            wr_addr <= next_addr(wr_addr, wr_burst, wr_size, wr_wrap_mask);
                            wr_len  <= wr_len - 1;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        // FIFO commit happens here (in FIFO control block).
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
    reg [DATA_WIDTH-1:0] fa_data;
    reg                  fa_uf;

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
    //  FIFO CONTROL
    //    PUSH (commit) on B-channel handshake; POP on FIXED read beats.
    // =====================================================================
    wire fifo_commit = (wr_state == WR_RESP) && s_axi_bvalid && s_axi_bready &&
                       (wr_burst == BURST_FIXED);

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            fifo_wr_ptr <= {PTR_W{1'b0}};
            fifo_rd_ptr <= {PTR_W{1'b0}};
            fifo_count  <= {(PTR_W+1){1'b0}};
        end else begin : fifo_ctrl
            integer i, pushed, popped, wp;
            wp = fifo_wr_ptr;
            pushed = 0;
            // COMMIT: move staged bytes into the FIFO at the B handshake
            if (fifo_commit) begin
                for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                    if ((i < stg_store) && ((fifo_count + pushed) < FIFO_DEPTH)) begin
                        fifo_mem[wp % FIFO_DEPTH] <= stg_mem[i];
                        wp     = wp + 1;
                        pushed = pushed + 1;
                    end
                end
            end
            // POP: oldest bytes for a FIXED read beat
            popped = 0;
            if (fifo_pop_req)
                popped = (fifo_pop_count <= fifo_count) ? fifo_pop_count : fifo_count;

            fifo_wr_ptr <= wp % FIFO_DEPTH;
            fifo_rd_ptr <= (fifo_rd_ptr + popped) % FIFO_DEPTH;
            fifo_count  <= fifo_count + pushed - popped;
        end
    end

endmodule
