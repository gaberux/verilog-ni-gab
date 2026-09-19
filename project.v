`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);

  // ---------------- VGA ----------------
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  reg  [1:0] R, G, B;

  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 0;
  assign uio_oe  = 0;
  wire _unused_ok = &{ena, uio_in, ui_in[7]};

  hvsync_generator hvsync_gen(
    .clk(clk), .reset(~rst_n),
    .hsync(hsync), .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x), .vpos(pix_y)
  );

  // ---------------- Gamepad (arrow keys) ----------------
  wire [1:0] gp_up, gp_down, gp_left, gp_right;
  wire [1:0] gp_b, gp_y, gp_sel, gp_start, gp_a, gp_x, gp_l, gp_r, gp_present;

  gamepad_pmod_dual gamepad (
    .rst_n(rst_n), .clk(clk),
    .pmod_data(ui_in[6]), .pmod_clk(ui_in[5]), .pmod_latch(ui_in[4]),
    .b(gp_b), .y(gp_y), .select(gp_sel), .start(gp_start),
    .up(gp_up), .down(gp_down), .left(gp_left), .right(gp_right),
    .a(gp_a), .x(gp_x), .l(gp_l), .r(gp_r),
    .is_present(gp_present)
  );

  wire _unused_gp = &{gp_b, gp_y, gp_sel, gp_start, gp_a, gp_x, gp_l, gp_r, gp_present};

  // direction = gamepad (arrow keys) OR ui_in[3:0] buttons
  // bit0 = up, bit1 = down, bit2 = left, bit3 = right
  wire [3:0] dir = {|gp_right, |gp_left, |gp_down, |gp_up} | ui_in[3:0];

  // ---------------- Levels ----------------
  // 00 empty | 01 dirt | 10 wall | 11 diamond
  // level: 0 = easy (6 gems), 1 = medium (6 gems, tighter maze), 2 = hard (7 gems, tightest maze)
  function [1:0] get_tile(input [3:0] c, input [2:0] r, input [1:0] lvl);
    reg [19:0] rowdata;
    reg [4:0]  sh;
    begin
      case (lvl)
        2'd0: begin
          case (r)
            3'd0: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            3'd1: rowdata = 20'b10_00_01_01_01_11_01_01_01_10;
            3'd2: rowdata = 20'b10_11_01_10_01_01_01_10_01_10;
            3'd3: rowdata = 20'b10_01_11_01_01_10_01_01_11_10;
            3'd4: rowdata = 20'b10_01_01_01_10_01_01_01_11_10;
            3'd5: rowdata = 20'b10_01_01_11_01_01_01_10_01_10;
            3'd6: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            default: rowdata = 20'd0;
          endcase
        end
        2'd1: begin
          case (r)
            3'd0: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            3'd1: rowdata = 20'b10_00_01_01_01_01_01_01_10_10;
            3'd2: rowdata = 20'b10_10_11_01_10_01_01_11_01_10;
            3'd3: rowdata = 20'b10_01_10_01_10_01_01_10_10_10;
            3'd4: rowdata = 20'b10_10_10_01_10_01_01_01_01_10;
            3'd5: rowdata = 20'b10_01_01_01_01_11_11_11_11_10;
            3'd6: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            default: rowdata = 20'd0;
          endcase
        end
        default: begin // level 2 (hardest)
          case (r)
            3'd0: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            3'd1: rowdata = 20'b10_00_01_10_10_01_11_01_10_10;
            3'd2: rowdata = 20'b10_01_01_11_11_10_10_11_10_10;
            3'd3: rowdata = 20'b10_10_11_01_10_10_10_01_10_10;
            3'd4: rowdata = 20'b10_01_01_01_01_01_01_11_10_10;
            3'd5: rowdata = 20'b10_01_01_01_10_01_01_01_11_10;
            3'd6: rowdata = 20'b10_10_10_10_10_10_10_10_10_10;
            default: rowdata = 20'd0;
          endcase
        end
      endcase
      sh = {(4'd9 - c), 1'b0};
      get_tile = (c > 4'd9) ? 2'b10 : rowdata[sh +: 2];
    end
  endfunction

  function [6:0] cell_idx(input [3:0] c, input [2:0] r);
    cell_idx = {4'b0, r} * 7'd10 + {3'b0, c};
  endfunction

  localparam [3:0] EXIT_C = 4'd8;
  localparam [2:0] EXIT_R = 3'd6;

  // per-level gem target and time limit
  function [2:0] level_total(input [1:0] lvl);
    case (lvl)
      2'd0: level_total = 3'd6;
      2'd1: level_total = 3'd6;
      default: level_total = 3'd7;
    endcase
  endfunction

  function [7:0] level_time(input [1:0] lvl);
    case (lvl)
      2'd0: level_time = 8'd90;
      2'd1: level_time = 8'd70;
      default: level_time = 8'd50;
    endcase
  endfunction

  // ---------------- Enemy config (4 slots, rows fixed) ----------------
  localparam [2:0] E0_ROW = 3'd2;
  localparam [2:0] E1_ROW = 3'd4;
  localparam [2:0] E2_ROW = 3'd1;
  localparam [2:0] E3_ROW = 3'd5;
  localparam [3:0] E_MIN_C = 4'd1;
  localparam [3:0] E_MAX_C = 4'd8;

  reg  [1:0]  level;

  wire active0 = 1'b1;              // always on
  wire active1 = 1'b1;              // always on
  wire active2 = (level >= 2'd1);   // from level 1
  wire active3 = (level >= 2'd2);   // only hardest level

  wire enemy_tick = (level == 2'd0) ? (frame[4:0] == 5'b00000) :
                     (level == 2'd1) ? (frame[3:0] == 4'b0000) :
                                        (frame[2:0] == 3'b000);

  // ---------------- Game state ----------------
  reg [3:0]  pc;
  reg [2:0]  pr;
  reg [69:0] dug;
  reg [2:0]  gems;
  reg        win;
  reg        game_over;
  reg [3:0]  prev_in;
  reg [5:0]  frame;
  reg [7:0]  time_left;
  reg [6:0]  win_delay;

  reg [3:0]  e0c, e1c, e2c, e3c;
  reg        e0dir, e1dir, e2dir, e3dir;

  wire [3:0] pressed = dir & ~prev_in;
  wire       frozen  = win || game_over;
  wire [2:0] TOTAL    = level_total(level);
  wire [7:0] TIME_LIM = level_time(level);

  reg [3:0] nc;
  reg [2:0] nr;
  reg       moving;
  always @* begin
    nc = pc; nr = pr; moving = 1'b1;
    if      (pressed[0]) nr = pr - 3'd1;
    else if (pressed[1]) nr = pr + 3'd1;
    else if (pressed[2]) nc = pc - 4'd1;
    else if (pressed[3]) nc = pc + 4'd1;
    else                 moving = 1'b0;
  end

  wire       inb       = (nc <= 4'd9) && (nr <= 3'd6);
  wire [1:0] tt        = get_tile(nc, nr, level);
  wire [6:0] nidx      = cell_idx(nc, nr);
  wire       is_exit   = (nc == EXIT_C) && (nr == EXIT_R);
  wire       door_open = (gems == TOTAL);
  wire       blocked   = (tt == 2'b10) && !(is_exit && door_open);

  wire hit0 = active0 && (pc == e0c) && (pr == E0_ROW);
  wire hit1 = active1 && (pc == e1c) && (pr == E1_ROW);
  wire hit2 = active2 && (pc == e2c) && (pr == E2_ROW);
  wire hit3 = active3 && (pc == e3c) && (pr == E3_ROW);
  wire any_hit = hit0 || hit1 || hit2 || hit3;

  always @(posedge clk) begin
    if (~rst_n) begin
      pc <= 4'd1; pr <= 3'd1;
      dug <= 70'd0; gems <= 3'd0;
      win <= 1'b0; game_over <= 1'b0;
      prev_in <= 4'd0; frame <= 6'd0;
      level <= 2'd0;
      time_left <= 8'd90;
      win_delay <= 7'd0;
      e0c <= E_MIN_C; e0dir <= 1'b1;
      e1c <= E_MAX_C; e1dir <= 1'b0;
      e2c <= E_MIN_C; e2dir <= 1'b1;
      e3c <= E_MAX_C; e3dir <= 1'b0;
    end else begin
      prev_in <= dir;

      // ---- Player movement (frozen on win or game over) ----
      if (moving && inb && !blocked && !frozen) begin
        pc <= nc;
        pr <= nr;
        if (tt == 2'b11 && !dug[nidx]) gems <= gems + 1'b1;
        if (tt == 2'b01 || tt == 2'b11) dug[nidx] <= 1'b1;
        if (is_exit) win <= 1'b1;
      end

      // ---- Per-video-frame updates: enemies + timer ----
      if (pix_x == 0 && pix_y == 0) begin
        frame <= frame + 1'b1;

        if (!frozen) begin
          if (enemy_tick) begin
            if (active0) begin
              if (e0dir) begin
                if (e0c >= E_MAX_C) begin e0c <= e0c - 1'b1; e0dir <= 1'b0; end
                else                 e0c <= e0c + 1'b1;
              end else begin
                if (e0c <= E_MIN_C) begin e0c <= e0c + 1'b1; e0dir <= 1'b1; end
                else                 e0c <= e0c - 1'b1;
              end
            end
            if (active1) begin
              if (e1dir) begin
                if (e1c >= E_MAX_C) begin e1c <= e1c - 1'b1; e1dir <= 1'b0; end
                else                 e1c <= e1c + 1'b1;
              end else begin
                if (e1c <= E_MIN_C) begin e1c <= e1c + 1'b1; e1dir <= 1'b1; end
                else                 e1c <= e1c - 1'b1;
              end
            end
            if (active2) begin
              if (e2dir) begin
                if (e2c >= E_MAX_C) begin e2c <= e2c - 1'b1; e2dir <= 1'b0; end
                else                 e2c <= e2c + 1'b1;
              end else begin
                if (e2c <= E_MIN_C) begin e2c <= e2c + 1'b1; e2dir <= 1'b1; end
                else                 e2c <= e2c - 1'b1;
              end
            end
            if (active3) begin
              if (e3dir) begin
                if (e3c >= E_MAX_C) begin e3c <= e3c - 1'b1; e3dir <= 1'b0; end
                else                 e3c <= e3c + 1'b1;
              end else begin
                if (e3c <= E_MIN_C) begin e3c <= e3c + 1'b1; e3dir <= 1'b1; end
                else                 e3c <= e3c - 1'b1;
              end
            end
          end

          // Countdown timer, ticks roughly once per second (~64 frames)
          if (frame == 6'd63) begin
            if (time_left == 8'd0) game_over <= 1'b1;
            else                   time_left <= time_left - 1'b1;
          end
        end

        // ---- Level transition (only while winning, not on final level) ----
        if (win && level < 2'd2) begin
          if (win_delay == 7'd89) begin
            level     <= level + 1'b1;
            pc <= 4'd1; pr <= 3'd1;
            dug       <= 70'd0;
            gems      <= 3'd0;
            win       <= 1'b0;
            game_over <= 1'b0;
            win_delay <= 7'd0;
            time_left <= level_time(level + 1'b1);
            e0c <= E_MIN_C; e0dir <= 1'b1;
            e1c <= E_MAX_C; e1dir <= 1'b0;
            e2c <= E_MIN_C; e2dir <= 1'b1;
            e3c <= E_MAX_C; e3dir <= 1'b0;
          end else begin
            win_delay <= win_delay + 1'b1;
          end
        end
      end

      // ---- Hazard collision -> game over ----
      if (!frozen && any_hit) game_over <= 1'b1;
    end
  end

  // ---------------- Drawing ----------------
  wire [3:0] col = pix_x[9:6];
  wire [2:0] row = pix_y[8:6];
  wire [5:0] lx  = pix_x[5:0];
  wire [5:0] ly  = pix_y[5:0];

  wire [5:0] dx  = (lx >= 6'd32) ? lx - 6'd32 : 6'd32 - lx;
  wire [5:0] dy  = (ly >= 6'd32) ? ly - 6'd32 : 6'd32 - ly;
  wire [5:0] dyh = (ly >= 6'd16) ? ly - 6'd16 : 6'd16 - ly;
  wire [6:0] man   = {1'b0, dx} + {1'b0, dy};
  wire [6:0] man_h = {1'b0, dx} + {1'b0, dyh};
  wire [4:0] bx    = lx[4:0] + {ly[4], 4'b0};

  wire [1:0] t_raw  = get_tile(col, row, level);
  wire       is_dug = dug[cell_idx(col, row)];
  wire [1:0] t      = (row == 3'd7) ? 2'b00 : (is_dug ? 2'b00 : t_raw);

  wire final_win = win && (level == 2'd2);

  always @* begin
    R = 2'b00; G = 2'b00; B = 2'b00;
    if (video_active) begin
      if (game_over) begin
        // Flashing red "game over" screen
        {R, G, B} = frame[4] ? {2'b11, 2'b00, 2'b00} : {2'b01, 2'b00, 2'b00};
      end else if (row == 3'd7) begin
        // HUD: left side = gem pips (up to TOTAL), right 3 cols = level pips
        if (col < {1'b0, TOTAL} && man_h < 7'd13) begin
          {R, G, B} = ({1'b0, gems} > col) ? {2'b11, 2'b00, 2'b00}
                                           : {2'b01, 2'b01, 2'b01};
        end else if (col >= 4'd7 && man_h < 7'd13) begin
          {R, G, B} = ((col - 4'd7) <= {1'b0, level}) ? {2'b00, 2'b00, 2'b11}
                                                       : {2'b01, 2'b01, 2'b01};
        end
      end else begin
        if (final_win)      {R, G, B} = {2'b00, (frame[4] ? 2'b11 : 2'b01), 2'b00};
        else if (win)        {R, G, B} = frame[4] ? {2'b11, 2'b11, 2'b00} : {2'b01, 2'b01, 2'b00};
        else                 {R, G, B} = {2'b00, 2'b00, 2'b01};

        case (t)
          2'b01: begin // dirt
            {R, G, B} = {2'b10, 2'b01, 2'b00};
            if (lx[3:2] == 2'b10 && ly[3:2] == 2'b01) {R, G, B} = {2'b01, 2'b01, 2'b00};
          end
          2'b10: begin // wall
            {R, G, B} = {2'b10, 2'b10, 2'b10};
            if (ly[3:0] < 4'd2 || bx < 5'd2) {R, G, B} = {2'b01, 2'b01, 2'b01};
          end
          2'b11: begin // diamond
            if (man < 7'd22) {R, G, B} = {2'b11, 2'b00, 2'b00};
            if (man < 7'd8)  {R, G, B} = {2'b11, 2'b10, 2'b10};
          end
          default: ;
        endcase

        // exit door
        if (col == EXIT_C && row == EXIT_R) begin
          {R, G, B} = {2'b10, 2'b10, 2'b10};
          if (dx < 6'd20 && dy < 6'd24)
            {R, G, B} = door_open ? {2'b00, 2'b11, 2'b00} : {2'b10, 2'b00, 2'b00};
        end

        // hazards
        if (active0 && col == e0c && row == E0_ROW && man < 7'd20) {R, G, B} = {2'b11, 2'b01, 2'b11};
        if (active1 && col == e1c && row == E1_ROW && man < 7'd20) {R, G, B} = {2'b01, 2'b00, 2'b11};
        if (active2 && col == e2c && row == E2_ROW && man < 7'd20) {R, G, B} = {2'b11, 2'b11, 2'b00};
        if (active3 && col == e3c && row == E3_ROW && man < 7'd20) {R, G, B} = {2'b11, 2'b01, 2'b00};

        // player (may hat!)
        if (col == pc && row == pr) begin
          if (dx < 6'd16 && ly >= 6'd16 && ly < 6'd21) {R, G, B} = {2'b11, 2'b10, 2'b00};
          if (dx < 6'd9  && ly >= 6'd21 && ly < 6'd36) {R, G, B} = {2'b11, 2'b10, 2'b01};
          if (dx < 6'd11 && ly >= 6'd36 && ly < 6'd52) {R, G, B} = {2'b00, 2'b10, 2'b11};
        end
      end
    end
  end

endmodule

// =====================================================================
// Gamepad Pmod interface (Pat Deegan, Apache-2.0) - trimmed to what we use
// =====================================================================
module gamepad_pmod_driver #(
  parameter BIT_WIDTH = 24
) (
  input  wire rst_n,
  input  wire clk,
  input  wire pmod_data,
  input  wire pmod_clk,
  input  wire pmod_latch,
  output reg  [BIT_WIDTH-1:0] data_reg
);
  reg pmod_clk_prev;
  reg pmod_latch_prev;
  reg [BIT_WIDTH-1:0] shift_reg;

  reg [1:0] pmod_data_sync;
  reg [1:0] pmod_clk_sync;
  reg [1:0] pmod_latch_sync;

  always @(posedge clk) begin
    if (~rst_n) begin
      pmod_data_sync  <= 2'b0;
      pmod_clk_sync   <= 2'b0;
      pmod_latch_sync <= 2'b0;
    end else begin
      pmod_data_sync  <= {pmod_data_sync[0],  pmod_data};
      pmod_clk_sync   <= {pmod_clk_sync[0],   pmod_clk};
      pmod_latch_sync <= {pmod_latch_sync[0], pmod_latch};
    end
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      data_reg        <= {BIT_WIDTH{1'b1}};
      shift_reg       <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev   <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end else begin
      pmod_clk_prev   <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];

      if (pmod_latch_sync[1] & ~pmod_latch_prev)
        data_reg <= shift_reg;

      if (pmod_clk_sync[1] & ~pmod_clk_prev)
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
    end
  end
endmodule

module gamepad_pmod_decoder (
  input  wire [11:0] data_reg,
  output wire b, y, select, start, up, down, left, right, a, x, l, r,
  output wire is_present
);
  wire reg_empty = (data_reg == 12'hfff);
  assign is_present = reg_empty ? 1'b0 : 1'b1;
  assign {b, y, select, start, up, down, left, right, a, x, l, r} = reg_empty ? 12'd0 : data_reg;
endmodule

module gamepad_pmod_dual (
  input  wire rst_n,
  input  wire clk,
  input  wire pmod_data,
  input  wire pmod_clk,
  input  wire pmod_latch,
  output wire [1:0] b, y, select, start, up, down, left, right, a, x, l, r,
  output wire [1:0] is_present
);
  wire [23:0] gamepad_pmod_data;

  gamepad_pmod_driver driver (
    .rst_n(rst_n), .clk(clk),
    .pmod_data(pmod_data), .pmod_clk(pmod_clk), .pmod_latch(pmod_latch),
    .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder1 (
    .data_reg(gamepad_pmod_data[11:0]),
    .b(b[0]), .y(y[0]), .select(select[0]), .start(start[0]),
    .up(up[0]), .down(down[0]), .left(left[0]), .right(right[0]),
    .a(a[0]), .x(x[0]), .l(l[0]), .r(r[0]), .is_present(is_present[0])
  );

  gamepad_pmod_decoder decoder2 (
    .data_reg(gamepad_pmod_data[23:12]),
    .b(b[1]), .y(y[1]), .select(select[1]), .start(start[1]),
    .up(up[1]), .down(down[1]), .left(left[1]), .right(right[1]),
    .a(a[1]), .x(x[1]), .l(l[1]), .r(r[1]), .is_present(is_present[1])
  );
endmodule
