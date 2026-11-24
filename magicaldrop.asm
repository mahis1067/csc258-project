################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Saanvi Tyagi, 1011935541
# Student 2: Mahi Shah, 1011900187
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    512
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

##############################################################################
# GAME OVERVIEW AND CONTROLS
#   A / D : move the character left / right (stops at columns 0 and 6)
#   S     : grab the lowest bubble in the column and the same-coloured ones directly above it
#   W     : throw the held bubbles up into the column, under the lowest bubble
#   Q     : quit
#
# How a turn works:
#   1. Thrown bubbles stack under the lowest bubble of the column.
#   2. Trigger: a vertical run of 3 or more same-coloured bubbles (score = run length * 2).
#   3. Explosion: every bubble of that colour connected to the run (up, down, left, right)
#      is deleted too (flood fill).
#   4. Nothing else moves: bubbles that were below a deleted bubble stay exactly where
#      they are (no gravity), so only the exploded bubbles disappear.
#
# Other rules:
#   - Every 10 key presses a new random row is pushed in at the top (advance_row).
#   - The game ends if a bubble reaches the bottom row (row 13), or when the timer hits 0.
#
# Memory: the playing field is the 14 x 7 word array "grid" (row 0 = top, 0 = empty).
# It is drawn on screen at (col + 2, row + 5) by draw_field.
##############################################################################

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000

##############################################################################
# Mutable Data
##############################################################################
grey:   .word 0x808080
dark_grey: .word 0x404040     
white:  .word 0xFFFFFF

# Table of the 4 brick colours, picked from at random (index 0-3)
palette: .word 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00   # red, green, blue, yellow

# ---------------- Game variables (change these while playing) ----------------
fill_rows:   .word 4          # how many rows of bricks are filled from the top (max 14)
aim_x:       .word 5          # x column of the character and aiming line (centre of box)
held_colour: .word 0          # colour the character is holding (set at startup)
next_colour: .word 0          # colour that will be held next (set at startup)

# Stores the hex version of the mapping of segments for digits 0-9
# For the number 0, its used by segment a,b,c,d,e,f so binary rep would be 0111111 = 0x3F
seg_masks:
    .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

# per segment: dx, dy, length, direction (0 = horizontal, 1 = vertical)
seg_sizes:
    .byte 0,0,3,0       # segment a starts at 0,0 goes 3 horizontal
    .byte 2,0,3,1       # b upper right
    .byte 2,2,3,1       # c lower right
    .byte 0,4,3,0       # d bottom
    .byte 0,2,3,1       # e lower left
    .byte 0,0,3,1       # f upper left
    .byte 0,2,3,0       # g middle
    
# will be changed when game is played
left_digits:  .byte 0,4,2
score_digits: .byte 1,3,5,0,0

    .align 2
player_col:  .word 3          # grid column 0-6
held_count:  .word 0
key_count:   .word 0          # keys since the last new row
score:       .word 0          # current score (shown in the PTS counter)
time_left:   .word 60         # seconds remaining (shown in the LEFT counter)
last_time:   .word 0          # ms timestamp of the last timer tick
grid:        .space 392       # 14 x 7 cells, 4 bytes each, 0 = empty
game_over_msg: .asciiz "Game over!\n"
timeup_msg:    .asciiz "Time's up!\n"
    .align 2
dir_r:       .word -1, 1, 0, 0     # row change for up, down, left, right
dir_c:       .word 0, 0, -1, 1     # column change for up, down, left, right
mark:        .space 392            # 14 x 7 words, 1 = cell will be deleted this pass
fstack:      .space 392            # work list of cell indexes for the flood fill

##############################################################################
# Code
##############################################################################
	.text
	.globl main

main:
    lw $s5, grey            # colour
    li $s0, 1               # left x
    li $s1, 9               # right x
    li $s2, 4               # top y
    li $s3, 19              # bottom y

    move $s4, $s0

top_loop:
    bgt $s4, $s1, top_done   # if current x ($s4) is greater than right x, branch to top_done, loop otherwise
    move $a0, $s4            # copy current x to $a0 (x_pixel to paint)
    move $a1, $s2            # copy top y to $a1 (y_pixel to paint)
    jal draw_pixel           # jump to link draw_pixel
    addi $s4, $s4, 1         # increment 1 to x to move to the next coordinate
    j top_loop
    
top_done:
    move $s4, $s2            # change current x to current y (starting with top y)
    
right_loop:
    bgt $s4, $s3, right_done  # if current y ($s4) is greater than bottom y, branch to right_done, loop otherwise
    move $a0, $s1             # copy current x to #a0 (x_pixel to paint)
    move $a1, $s4             # copy current y to #a1 (y pixel to paint)
    jal draw_pixel            # jump to link draw_pixel
    addi $s4, $s4, 1          # increment 1 to y to move to the next coordinate
    j right_loop      

right_done:
    move $s4, $s0       # change current y to current x (starting with right x)

bottom_loop:
    bgt $s4, $s1, bottom_done   # if current x ($s4) is greater than left y, branch to bottom done, loop otherwise
    move $a0, $s4               # copy current x to #a0 (x_pixel to paint)
    move $a1, $s3               # copy current y to #a1 (y pixel to paint)
    jal draw_pixel              # jump to link draw_pixel
    addi $s4, $s4, 1            # increment 1 to x to move to the next coordinate
    j bottom_loop

bottom_done:
    move $s4, $s2      # change current x to current y (starting with top y)

left_loop:
    bgt $s4, $s3, bricks    # if current y ($s4) is greater than left y, branch to text, loop otherwise
    move $a0, $s0              # copy current x to #a0 (x_pixel to paint)
    move $a1, $s4              # copy current y to #a1 (y pixel to paint)
    jal draw_pixel             # jump to link draw_pixel
    addi $s4, $s4, 1           # increment y to x to move to the next coordinate
    j left_loop
    
# ---------------- Random coloured bricks inside the box ----------------
# Interior is x = left x+1 .. right x-1 and y = top y+1 downwards.
# Rows are filled top to bottom, each row left to right, random colour per brick.
bricks:
    lw $t0, fill_rows         # $t0 = how many rows to fill
    li $t1, 14                # $t1 = interior height (bottom y - top y - 1 = 14 rows)
    ble $t0, $t1, rows_ok     # if fill_rows <= 14 it fits in the box, keep it
    move $t0, $t1             # otherwise clamp it to 14 so we never draw over the border
rows_ok:
    addi $s6, $s2, 1          # $s6 = current y, starts at the first interior row (top y + 1)
    add  $s7, $s6, $t0        # $s7 = end y (exclusive) = first row + number of rows

brick_row:
    bge $s6, $s7, bricks_done # if current y reached end y, all rows are filled
    addi $s4, $s0, 1          # $s4 = current x, starts at the first interior column (left x + 1)

brick_col:
    bge $s4, $s1, brick_col_done  # if current x reached right x (the border), this row is full
    jal random_colour         # $v0 = a random colour from the palette
    move $s5, $v0             # use that colour for the next pixel
    move $a0, $s4             # $a0 = x of the brick
    move $a1, $s6             # $a1 = y of the brick
    jal draw_pixel            # paint the brick
    addi $s4, $s4, 1          # move right to the next brick
    j brick_col               # repeat for the next column

brick_col_done:
    addi $s6, $s6, 1          # move down to the next row
    j brick_row               # fill the next row

bricks_done:

# ---------------- Aiming line (dark grey dots, every second row) ----------------
# Starts 2 rows above the bottom border and goes up until it reaches the bricks.
aim_line:
    lw $s5, dark_grey         # dots are drawn in dark grey
    addi $s6, $s3, -2         # $s6 = current y, starts 2 rows above the bottom border
    lw $t0, fill_rows         # $t0 = number of brick rows
    li $t1, 14                # $t1 = maximum interior rows
    ble $t0, $t1, aim_ok      # if fill_rows <= 14 keep it
    move $t0, $t1             # otherwise clamp it to 14 (same as the bricks)
aim_ok:
    add $s7, $s2, $t0         # $s7 = last brick row y (top y + fill_rows), dots stop above this

aim_loop:
    ble $s6, $s7, aim_done    # if current y is at or above the last brick row, stop
    lw $a0, aim_x             # $a0 = x of the dot (the aiming column)
    move $a1, $s6             # $a1 = y of the dot
    jal draw_pixel            # paint the dot
    addi $s6, $s6, -2         # move up 2 rows to leave a gap between dots
    j aim_loop                # repeat for the next dot

aim_done:

# ---------------- Character, held colour and next colour ----------------
# Stacked below the box in column aim_x:
#   y = bottom y + 1 -> the character (white placeholder)
#   y = bottom y + 2 -> the colour it is holding
#   y = bottom y + 3 -> the next colour
shooter:
    lw $s5, white             # the character is drawn in white
    lw $a0, aim_x             # $a0 = x of the character
    addi $a1, $s3, 1          # $a1 = y just below the bottom border
    jal draw_pixel            # paint the character

    jal random_colour         # $v0 = random colour for the held brick
    sw $v0, held_colour       # remember it in memory so the game can use it later
    move $s5, $v0             # draw it in that colour
    lw $a0, aim_x             # $a0 = x (reloaded because random_colour changed $a0)
    addi $a1, $s3, 2          # $a1 = one row below the character
    jal draw_pixel            # paint the held colour

    jal random_colour         # $v0 = random colour for the next brick
    sw $v0, next_colour       # remember it in memory
    move $s5, $v0             # draw it in that colour
    lw $a0, aim_x             # $a0 = x (reloaded again)
    addi $a1, $s3, 3          # $a1 = two rows below the character
    jal draw_pixel            # paint the next colour

text:
    lw $s5, white             # switch the drawing colour to white for the text

    # ---------------- LEFT (y = 4..8) ----------------
    # L: vertical stem plus a bottom bar
    li $a0, 12                # x = 12 (left edge of the L)
    li $a1, 4                 # y = 4 (top of the letter)
    li $a2, 5                 # length 5 (full letter height)
    jal draw_vline            # draw the stem going down
    li $a0, 12                # x = 12
    li $a1, 8                 # y = 8 (bottom row of the letter)
    li $a2, 3                 # length 3 (full letter width)
    jal draw_hline            # draw the foot going right

    # E: stem plus top, middle and bottom bars
    li $a0, 16                # x = 16 (left edge of the E)
    li $a1, 4                 # y = 4 (top)
    li $a2, 5                 # length 5
    jal draw_vline            # draw the stem
    li $a0, 16                # x = 16
    li $a1, 4                 # y = 4 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top bar
    li $a0, 16                # x = 16
    li $a1, 6                 # y = 6 (middle row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the middle bar
    li $a0, 16                # x = 16
    li $a1, 8                 # y = 8 (bottom row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the bottom bar

    # F: stem plus top and middle bars
    li $a0, 20                # x = 20 (left edge of the F)
    li $a1, 4                 # y = 4 (top)
    li $a2, 5                 # length 5
    jal draw_vline            # draw the stem
    li $a0, 20                # x = 20
    li $a1, 4                 # y = 4 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top bar
    li $a0, 20                # x = 20
    li $a1, 6                 # y = 6 (middle row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the middle bar

    # T: top bar plus a centre stem
    li $a0, 24                # x = 24 (left edge of the T)
    li $a1, 4                 # y = 4 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top bar
    li $a0, 25                # x = 25 (centre column of the T)
    li $a1, 4                 # y = 4 (top)
    li $a2, 5                 # length 5
    jal draw_vline            # draw the stem

    # ---------------- PTS (y = 17..21) ----------------
    # P: stem, top bar, middle bar, and a right side for the bowl
    li $a0, 12                # x = 12 (left edge of the P)
    li $a1, 17                # y = 17 (top)
    li $a2, 5                 # length 5
    jal draw_vline            # draw the stem
    li $a0, 12                # x = 12
    li $a1, 17                # y = 17 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top of the bowl
    li $a0, 12                # x = 12
    li $a1, 19                # y = 19 (middle row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the bottom of the bowl
    li $a0, 14                # x = 14 (right edge of the P)
    li $a1, 17                # y = 17 (top)
    li $a2, 3                 # length 3 (rows 17-19)
    jal draw_vline            # draw the right side of the bowl

    # T: top bar plus a centre stem
    li $a0, 16                # x = 16 (left edge of the T)
    li $a1, 17                # y = 17 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top bar
    li $a0, 17                # x = 17 (centre column of the T)
    li $a1, 17                # y = 17 (top)
    li $a2, 5                 # length 5
    jal draw_vline            # draw the stem

    # S: three bars plus upper left and lower right sides
    li $a0, 20                # x = 20 (left edge of the S)
    li $a1, 17                # y = 17 (top row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the top bar
    li $a0, 20                # x = 20
    li $a1, 19                # y = 19 (middle row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the middle bar
    li $a0, 20                # x = 20
    li $a1, 21                # y = 21 (bottom row)
    li $a2, 3                 # length 3
    jal draw_hline            # draw the bottom bar
    li $a0, 20                # x = 20 (left side)
    li $a1, 17                # y = 17 (top)
    li $a2, 3                 # length 3 (rows 17-19)
    jal draw_vline            # draw the upper left side
    li $a0, 22                # x = 22 (right side)
    li $a1, 19                # y = 19 (middle)
    li $a2, 3                 # length 3 (rows 19-21)
    jal draw_vline            # draw the lower right side

    # ---------------- Numbers ----------------
    li $a0, 12                # x of the first digit slot
    li $a1, 10                # y of the LEFT counter row
    la $a2, left_digits       # address of the 3 digit bytes
    li $a3, 3                 # number of digits to draw
    jal draw_number           # draw the LEFT counter

    li $a0, 12                # x of the first digit slot
    li $a1, 23                # y of the score row
    la $a2, score_digits      # address of the 5 digit bytes
    li $a3, 5                 # number of digits to draw
    jal draw_number           # draw the score

    jal fill_grid             # fill the grid array in memory with random colours in the first fill_rows rows

    # ---------------- Start the countdown timer ----------------
    li   $v0, 30              # syscall 30 = system time in ms (low 32 bits come back in $a0)
    syscall
    sw   $a0, last_time       # remember "now" as the moment the last timer tick happened
    jal  draw_time            # draw the starting time (60) in the LEFT counter

##############################################################################
# Main game loop. Every frame: read a key, act on it, tick the timer,
# redraw the field and the character, then sleep for about 16 ms.
##############################################################################
game_loop:
    lw   $t0, ADDR_KBRD           # $t0 = address of the keyboard (first word = "key ready" flag)
    lw   $t1, 0($t0)              # $t1 = 1 if a key was pressed, otherwise 0
    bne  $t1, 1, redraw           # no key pressed: skip input handling and just redraw
    lw   $t2, 4($t0)              # $t2 = ASCII code of the key that was pressed
    beq  $t2, 0x71, quit          # q = quit
    beq  $t2, 0x61, key_left      # a = move left
    beq  $t2, 0x64, key_right     # d = move right
    beq  $t2, 0x73, key_grab      # s = grab bubbles from the column
    beq  $t2, 0x77, key_throw     # w = throw held bubbles into the column
    j    redraw                   # any other key is ignored

key_left:
    lw   $t3, player_col          # $t3 = current column (0 to 6)
    beq  $t3, 0, count_key        # already at the left edge: do not move, but still count the key
    addi $t3, $t3, -1             # move one column left
    sw   $t3, player_col          # save the new column
    j    count_key

key_right:
    lw   $t3, player_col          # $t3 = current column (0 to 6)
    beq  $t3, 6, count_key        # already at the right edge: do not move, but still count the key
    addi $t3, $t3, 1              # move one column right
    sw   $t3, player_col          # save the new column
    j    count_key

key_grab:
    jal  grab                     # take bubbles from the lowest part of this column into held_count
    j    count_key

key_throw:
    jal  throw                    # place held bubbles in this column, then resolve matches
                                  # (falls through into count_key)

count_key:
    lw   $t3, key_count           # $t3 = keys pressed since the last new row
    addi $t3, $t3, 1              # count this key
    sw   $t3, key_count
    blt  $t3, 10, redraw          # fewer than 10 keys so far: no new row yet
    sw   $zero, key_count         # every 10 keys: reset the counter ...
    jal  advance_row              # ... and push a new row in at the top (may end the game)

redraw:
    jal  update_timer             # tick the countdown once per real second (ends the game at 0)
    jal  draw_field               # draw the grid bubbles and the aiming dots
    jal  draw_player              # draw the character and its held bubbles
    li   $v0, 32                  # syscall 32 = sleep
    li   $a0, 16                  # 16 ms, which gives roughly 60 frames per second
    syscall
    j    game_loop                # next frame

game_over:
    li   $v0, 4                   # syscall 4 = print string
    la   $a0, game_over_msg       # "Game over!"
    syscall
quit:
    li   $v0, 10                  # syscall 10 = exit the program
    syscall

random_colour:
    li $v0, 42              # syscall 42 = random integer in a range
    li $a0, 0               # random number generator id 0
    li $a1, 4               # upper bound (exclusive): result will be 0, 1, 2 or 3
    syscall                 # the random number is returned in $a0
    sll $a0, $a0, 2         # multiply index by 4 (each palette entry is a 4-byte word)
    la  $t0, palette        # $t0 = address of the palette table
    add $t0, $t0, $a0       # $t0 = address of the chosen colour
    lw  $v0, 0($t0)         # $v0 = the chosen colour
    jr  $ra                 # return to the caller

##############################################################################
# draw_number: $a0 = x of first digit, $a1 = y,
#              $a2 = address of digit bytes, $a3 = how many digits
# Each digit gets a 4-pixel slot (3 wide + 1 gap).
##############################################################################

draw_number:
    addi $sp, $sp, -20      # make room for 5 words on the stack
    sw   $ra, 0($sp)        # save the return address (we call other functions)
    sw   $s0, 4($sp)        # save $s0 so the caller's value survives
    sw   $s1, 8($sp)        # save $s1
    sw   $s2, 12($sp)       # save $s2
    sw   $s3, 16($sp)       # save $s3

    move $s0, $a0           # $s0 = current x (moves right each digit)
    move $s1, $a1           # $s1 = y (same for every digit)
    move $s2, $a2           # $s2 = pointer to the current digit byte
    move $s3, $a3           # $s3 = digits remaining

num_loop:
    beqz $s3, num_done      # if no digits remain, we are finished
    move $a0, $s0           # $a0 = x of this digit's slot
    move $a1, $s1           # $a1 = y of this digit's slot
    lb   $a2, 0($s2)        # $a2 = the digit value 0-9 from memory
    jal  draw_digit         # draw this digit
    addi $s0, $s0, 4        # move x right by 4 (3 wide + 1 gap)
    addi $s2, $s2, 1        # point at the next digit byte
    addi $s3, $s3, -1       # one fewer digit remaining
    j    num_loop           # repeat for the next digit

num_done:
    lw   $ra, 0($sp)        # restore the return address
    lw   $s0, 4($sp)        # restore $s0
    lw   $s1, 8($sp)        # restore $s1
    lw   $s2, 12($sp)       # restore $s2
    lw   $s3, 16($sp)       # restore $s3
    addi $sp, $sp, 20       # free the stack space
    jr   $ra                # return to the caller

##############################################################################
# draw_digit: $a0 = x, $a1 = y, $a2 = digit 0-9, $s5 = colour
# Erases the slot in black first, then draws the digit.
##############################################################################
draw_digit:
    addi $sp, $sp, -8       # make room for 2 words
    sw   $ra, 0($sp)        # save the return address
    sw   $s5, 4($sp)        # save the real colour (we overwrite it with black)

    move $t4, $a0           # $t4 = base x of this digit
    move $t5, $a1           # $t5 = base y of this digit
    la   $t0, seg_masks     # $t0 = address of the mask table
    add  $t0, $t0, $a2      # move to this digit's entry (1 byte per digit)
    lb   $t9, 0($t0)        # $t9 = this digit's segment mask

    li   $s5, 0             # colour = black (0x000000)
    li   $a3, 0x7F          # mask with all 7 segments on
    jal  draw_segments      # draw every segment in black to erase the old digit

    lw   $s5, 4($sp)        # restore the real colour
    move $a3, $t9           # $a3 = this digit's mask
    jal  draw_segments      # draw only this digit's segments

    lw   $ra, 0($sp)        # restore the return address
    addi $sp, $sp, 8        # free the stack space
    jr   $ra                # return to the caller

##############################################################################
# draw_segments: $a3 = mask, $t4 = base x, $t5 = base y, $s5 = colour
##############################################################################
draw_segments:
    addi $sp, $sp, -4       # make room for 1 word
    sw   $ra, 0($sp)        # save the return address
    li   $t7, 0             # $t7 = segment index, 0 to 6 (a to g)
    la   $t8, seg_sizes     # $t8 = pointer to this segment's 4-byte entry

seg_next:
    beq  $t7, 7, seg_end    # after segment g (index 6), we are finished
    srlv $t0, $a3, $t7      # shift the mask right by the segment index
    andi $t0, $t0, 1        # keep only the lowest bit: 1 = segment is on
    beqz $t0, seg_skip      # if the bit is 0, skip drawing this segment

    lb   $a0, 0($t8)        # $a0 = dx for this segment
    add  $a0, $a0, $t4      # x = base x + dx
    lb   $a1, 1($t8)        # $a1 = dy for this segment
    add  $a1, $a1, $t5      # y = base y + dy
    lb   $a2, 2($t8)        # $a2 = length of this segment
    lb   $t0, 3($t8)        # $t0 = direction (0 = horizontal, 1 = vertical)
    beqz $t0, seg_h         # if direction is 0, draw a horizontal line
    jal  draw_vline         # otherwise draw a vertical line
    j    seg_skip           # done with this segment, go to the next
seg_h:
    jal  draw_hline         # draw the horizontal line

seg_skip:
    addi $t8, $t8, 4        # move the table pointer to the next segment entry
    addi $t7, $t7, 1        # next segment index
    j    seg_next           # repeat for the next segment

seg_end:
    lw   $ra, 0($sp)        # restore the return address
    addi $sp, $sp, 4        # free the stack space
    jr   $ra                # return to the caller

##############################################################################
# Line helpers: $a0 = x, $a1 = y, $a2 = length
##############################################################################
draw_hline:
    addi $sp, $sp, -4       # make room for 1 word
    sw   $ra, 0($sp)        # save the return address (we call draw_pixel)
    move $t2, $a0           # $t2 = current x
    add  $t3, $a0, $a2      # $t3 = end x (exclusive) = start x + length
hl_loop:
    bge  $t2, $t3, hl_done  # if current x reached end x, the line is finished
    move $a0, $t2           # $a0 = x of the pixel to paint ($a1 = y is unchanged)
    jal  draw_pixel         # paint the pixel
    addi $t2, $t2, 1        # move right by one pixel
    j    hl_loop            # repeat
hl_done:
    lw   $ra, 0($sp)        # restore the return address
    addi $sp, $sp, 4        # free the stack space
    jr   $ra                # return to the caller

draw_vline:
    addi $sp, $sp, -4       # make room for 1 word
    sw   $ra, 0($sp)        # save the return address (we call draw_pixel)
    move $t2, $a1           # $t2 = current y
    add  $t3, $a1, $a2      # $t3 = end y (exclusive) = start y + length
vl_loop:
    bge  $t2, $t3, vl_done  # if current y reached end y, the line is finished
    move $a1, $t2           # $a1 = y of the pixel to paint ($a0 = x is unchanged)
    jal  draw_pixel         # paint the pixel
    addi $t2, $t2, 1        # move down by one pixel
    j    vl_loop            # repeat
vl_done:
    lw   $ra, 0($sp)        # restore the return address
    addi $sp, $sp, 4        # free the stack space
    jr   $ra                # return to the caller

##############################################################################
# draw_pixel: $a0 = x, $a1 = y, $s5 = colour   (clobbers $t0, $t1)
##############################################################################
draw_pixel:
    sll $t0, $a1, 6         # $t0 = y * 64 (shifting left 6 bits = multiply by 2^6)
    add $t0, $t0, $a0       # $t0 = y * 64 + x (the unit index in the display)
    sll $t0, $t0, 2         # $t0 = unit index * 4 (each unit is a 4-byte word)
    lw  $t1, ADDR_DSPL      # $t1 = base address of the display
    add $t0, $t0, $t1       # $t0 = address of this pixel
    sw  $s5, 0($t0)         # store the colour into that pixel
    jr  $ra                 # return to the caller

##############################################################################
# grid_addr: $a0 = row, $a1 = col
#   returns $v0 = address of grid cell (row, col) = grid + (row * 7 + col) * 4
#   (the grid has 7 columns and each cell is one 4-byte word). Changes $t0 only.
##############################################################################
grid_addr:
    li   $t0, 7                 # number of columns per row
    mul  $t0, $a0, $t0          # $t0 = row * 7
    add  $t0, $t0, $a1          # $t0 = row * 7 + col (the cell index)
    sll  $t0, $t0, 2            # $t0 = cell index * 4 (byte offset)
    la   $v0, grid              # $v0 = address of the first cell
    add  $v0, $v0, $t0          # $v0 = address of this cell
    jr   $ra

##############################################################################
# fill_grid: put a random colour in every cell of the first fill_rows rows
# (the other rows stay 0 = empty). Only changes the grid array, does not draw.
##############################################################################
fill_grid:
    addi $sp, $sp, -12          # save $ra and the two saved registers we use
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    li   $s0, 0                 # $s0 = row
fg_row:
    lw   $t0, fill_rows         # number of rows to fill
    bge  $s0, $t0, fg_done      # all requested rows filled
    li   $s1, 0                 # $s1 = col
fg_col:
    bge  $s1, 7, fg_next_row    # finished this row
    jal  random_colour          # $v0 = random colour from the palette
    move $t1, $v0               # keep the colour ($t1 survives grid_addr)
    move $a0, $s0               # row
    move $a1, $s1               # col
    jal  grid_addr              # $v0 = address of this cell
    sw   $t1, 0($v0)            # store the colour in the cell
    addi $s1, $s1, 1            # next column
    j    fg_col
fg_next_row:
    addi $s0, $s0, 1            # next row
    j    fg_row
fg_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    addi $sp, $sp, 12
    jr   $ra

##############################################################################
# draw_field: draw every grid cell on the screen at (col + 2, row + 5).
# Empty cells are black, except that in the character's column every second
# empty row is drawn dark grey to make the aiming line.
##############################################################################
draw_field:
    addi $sp, $sp, -16          # save $ra, $s0, $s1 and $s5 (the drawing colour)
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s5, 12($sp)
    li   $s0, 0                 # $s0 = row
df_row:
    bge  $s0, 14, df_done       # all 14 rows drawn
    li   $s1, 0                 # $s1 = col
df_col:
    bge  $s1, 7, df_next_row    # all 7 columns of this row drawn
    move $a0, $s0               # row
    move $a1, $s1               # col
    jal  grid_addr              # $v0 = address of this cell
    lw   $s5, 0($v0)            # $s5 = colour in the cell (0 = empty = black)
    bne  $s5, 0, df_draw        # a bubble is here: draw it
    lw   $t0, player_col        # empty cell: is it in the character's column?
    bne  $s1, $t0, df_draw      # no: draw it black
    andi $t0, $s0, 1            # yes: is the row even?
    bne  $t0, 0, df_draw        # odd row: draw it black (gap between dots)
    lw   $s5, dark_grey         # even empty row in the aiming column: dark grey dot
df_draw:
    addi $a0, $s1, 2            # screen x = col + 2 (inside the left border)
    addi $a1, $s0, 5            # screen y = row + 5 (inside the top border)
    jal  draw_pixel             # paint the cell with the colour in $s5
    addi $s1, $s1, 1            # next column
    j    df_col
df_next_row:
    addi $s0, $s0, 1            # next row
    j    df_row
df_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s5, 12($sp)
    addi $sp, $sp, 16
    jr   $ra

##############################################################################
# draw_player: clear the area below the field (y = 20..30), then draw the white
# character at y = 20 and the held bubbles in a vertical line under it (max 10).
##############################################################################
draw_player:
    addi $sp, $sp, -12          # save $ra, $s0 and $s5
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s5, 8($sp)
    li   $s5, 0                 # colour = black, used to erase
    li   $s0, 20                # $s0 = first row to clear
dp_clear:
    bgt  $s0, 30, dp_draw       # rows 20 to 30 cleared
    li   $a0, 2                 # x = 2 (first field column)
    move $a1, $s0               # y = current row
    li   $a2, 7                 # length 7 (all 7 field columns)
    jal  draw_hline             # erase one row
    addi $s0, $s0, 1            # next row
    j    dp_clear
dp_draw:
    lw   $s5, white             # the character is white
    lw   $a0, player_col        # grid column of the character
    addi $a0, $a0, 2            # screen x = col + 2
    li   $a1, 20                # screen y = 20 (just below the field)
    jal  draw_pixel             # draw the character
    lw   $a2, held_count        # number of bubbles held
    ble  $a2, 10, dp_len_ok     # up to 10 fit below the character
    li   $a2, 10                # cap the drawn length at 10
dp_len_ok:
    lw   $s5, held_colour       # held bubbles use the held colour
    lw   $a0, player_col
    addi $a0, $a0, 2            # same screen x as the character
    li   $a1, 21                # start right under the character
    jal  draw_vline             # draw held_count pixels going down (nothing if 0)
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s5, 8($sp)
    addi $sp, $sp, 12
    jr   $ra

##############################################################################
# grab: take the lowest bubble in the character's column and every directly
# connected bubble of the same colour above it. Taken cells become empty and
# held_count goes up. If bubbles are already held, only the same colour can be added.
##############################################################################
grab:
    addi $sp, $sp, -16          # save $ra, $s0, $s1, $s2
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s2, 12($sp)
    lw   $s1, player_col        # $s1 = column to grab from
    li   $s0, 13                # $s0 = row, start at the bottom row and look upwards
gr_find:
    blt  $s0, 0, gr_done        # went past row 0: the column is empty, nothing to grab
    move $a0, $s0               # row
    move $a1, $s1               # col
    jal  grid_addr
    lw   $t1, 0($v0)            # colour in this cell
    bne  $t1, 0, gr_found       # first non-empty cell = the lowest bubble
    addi $s0, $s0, -1           # empty: look one row higher
    j    gr_find
gr_found:
    move $s2, $t1               # $s2 = colour of the lowest bubble
    lw   $t2, held_count        # are we already holding something?
    beq  $t2, 0, gr_take        # no: take it freely
    lw   $t3, held_colour       # yes: the colour must match what we hold
    bne  $s2, $t3, gr_done      # different colour: grab nothing
gr_take:
    blt  $s0, 0, gr_save        # reached the top of the column
    move $a0, $s0               # row
    move $a1, $s1               # col
    jal  grid_addr
    lw   $t1, 0($v0)            # colour of this cell
    bne  $t1, $s2, gr_save      # different colour (or empty): stop taking
    sw   $zero, 0($v0)          # remove the bubble from the grid
    lw   $t2, held_count
    addi $t2, $t2, 1            # one more bubble held
    sw   $t2, held_count
    addi $s0, $s0, -1           # go up one row
    j    gr_take
gr_save:
    sw   $s2, held_colour       # remember the colour we are holding
gr_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s2, 12($sp)
    addi $sp, $sp, 16
    jr   $ra

##############################################################################
# advance_row: if any bubble is in the bottom row (row 13) the game is over.
# Otherwise shift every row down by one and fill row 0 with a new random row.
##############################################################################
advance_row:
    addi $sp, $sp, -12          # save $ra, $s0, $s1
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    li   $s1, 0                 # $s1 = col, check row 13 first
ar_check:
    bge  $s1, 7, ar_shift_start # row 13 is empty in every column: safe to shift
    li   $a0, 13                # bottom row
    move $a1, $s1
    jal  grid_addr
    lw   $t1, 0($v0)
    bne  $t1, 0, game_over      # a bubble would be pushed out of the field: game over
    addi $s1, $s1, 1            # next column
    j    ar_check
ar_shift_start:
    li   $s0, 13                # $s0 = row to fill, start at the bottom and go up
ar_shift_row:
    beq  $s0, 0, ar_new_row     # rows 13..1 now hold the old rows above them
    li   $s1, 0                 # $s1 = col
ar_shift_col:
    bge  $s1, 7, ar_shift_next  # this row is done
    addi $a0, $s0, -1           # row above
    move $a1, $s1
    jal  grid_addr
    lw   $t1, 0($v0)            # $t1 = the colour in the cell above
    move $a0, $s0               # this row
    move $a1, $s1
    jal  grid_addr
    sw   $t1, 0($v0)            # copy it down into this cell
    addi $s1, $s1, 1            # next column
    j    ar_shift_col
ar_shift_next:
    addi $s0, $s0, -1           # go up one row (copying from the bottom up avoids overwriting)
    j    ar_shift_row
ar_new_row:
    li   $s1, 0                 # $s1 = col, fill row 0 with new random colours
ar_new_col:
    bge  $s1, 7, ar_done
    jal  random_colour          # $v0 = random colour
    move $t1, $v0
    li   $a0, 0                 # row 0
    move $a1, $s1
    jal  grid_addr
    sw   $t1, 0($v0)            # store the colour
    addi $s1, $s1, 1            # next column
    j    ar_new_col
ar_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    addi $sp, $sp, 12
    jr   $ra

##############################################################################
# MILESTONE 3
##############################################################################

##############################################################################
# throw: put the held bubbles into the character's column, directly under the
# lowest bubble (or at the top if the column is empty), then resolve matches.
# Does nothing if no bubbles are held.
##############################################################################
throw:
    addi $sp, $sp, -20          # save $ra, $s0 to $s3
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s2, 12($sp)
    sw   $s3, 16($sp)
    lw   $t0, held_count
    beqz $t0, th_done           # nothing held: nothing to throw
    lw   $s1, player_col        # $s1 = column to throw into
    li   $s0, 13                # $s0 = row, search upwards from the bottom
th_find:
    blt  $s0, 0, th_place       # empty column: $s0 = -1
    move $a0, $s0
    move $a1, $s1
    jal  grid_addr
    lw   $t1, 0($v0)
    bne  $t1, 0, th_place       # found the lowest bubble in the column
    addi $s0, $s0, -1           # empty: look one row higher
    j    th_find
th_place:
    addi $s0, $s0, 1            # $s0 = first free row under the stack
    lw   $s2, held_colour       # $s2 = colour being thrown
    lw   $s3, held_count        # $s3 = how many bubbles are left to place
th_loop:
    beqz $s3, th_end            # all placed
    bgt  $s0, 13, th_end        # no room left in the column: the rest are dropped
    move $a0, $s0
    move $a1, $s1
    jal  grid_addr
    sw   $s2, 0($v0)            # put one bubble in this cell
    addi $s0, $s0, 1            # next row down
    addi $s3, $s3, -1           # one fewer to place
    j    th_loop
th_end:
    sw   $zero, held_count      # hands are empty now
    jal  resolve_board          # find vertical triggers and delete the exploded bubbles
th_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s2, 12($sp)
    lw   $s3, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

##############################################################################
# resolve_board: find every vertical run of 3+ (the triggers), flood fill from each
# one to mark all connected same-coloured bubbles, then delete only the marked
# bubbles. No other bubble moves. Score per trigger = run length * 2.
# Registers: $s0 = row, $s1 = col, $s2 = run colour, $s3 = end of run,
#            $s4 = 1 if this pass found a trigger.
##############################################################################
resolve_board:
    addi $sp, $sp, -24          # save $ra, $s0 to $s4
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s2, 12($sp)
    sw   $s3, 16($sp)
    sw   $s4, 20($sp)
    jal  clear_marks            # start with nothing marked for deletion
    li   $s4, 0                 # no trigger found yet
    li   $s1, 0                 # start at column 0
rb_col:
    bge  $s1, 7, rb_scan_done   # all columns scanned
    li   $s0, 0                 # start at the top row of this column
rb_row:
    bge  $s0, 14, rb_col_next   # reached the bottom of the column
    move $a0, $s0
    move $a1, $s1
    jal  grid_addr
    lw   $s2, 0($v0)            # colour at (row, col)
    bnez $s2, rb_run            # a bubble: measure the vertical run starting here
    addi $s0, $s0, 1            # empty: next row
    j    rb_row
rb_run:
    addi $s3, $s0, 1            # end of the vertical run (exclusive), at least this one cell
rb_ext:
    bge  $s3, 14, rb_end        # hit the bottom of the grid
    move $a0, $s3
    move $a1, $s1
    jal  grid_addr
    lw   $t1, 0($v0)            # colour of the next cell down
    bne  $t1, $s2, rb_end       # different colour or empty: the run ends
    addi $s3, $s3, 1            # same colour: the run is one longer
    j    rb_ext
rb_end:
    sub  $t2, $s3, $s0          # $t2 = run length
    blt  $t2, 3, rb_next        # shorter than 3: not a trigger
    sll  $a0, $t2, 1            # points = run length * 2
    jal  add_score              # add to the score and redraw it
    li   $s4, 1                 # remember that this pass found a trigger
    move $a0, $s0               # flood fill from the first cell of the run:
    move $a1, $s1               #   row
    move $a2, $s2               #   col and colour
    jal  flood_fill             # marks the run and all connected same-coloured bubbles
rb_next:
    move $s0, $s3               # continue scanning after this run
    j    rb_row
rb_col_next:
    addi $s1, $s1, 1            # next column
    j    rb_col
rb_scan_done:
    beqz $s4, rb_finish         # no trigger found: nothing to delete
    jal  delete_marked          # delete every marked bubble; all other bubbles stay where they are
rb_finish:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s2, 12($sp)
    lw   $s3, 16($sp)
    lw   $s4, 20($sp)
    addi $sp, $sp, 24
    jr   $ra

##############################################################################
# flood_fill: $a0 = row, $a1 = col, $a2 = colour.
# Marks every cell of that colour that is connected to (row, col) by up, down,
# left or right steps. "fstack" is a work list of cell indexes still to visit.
# A cell index is row * 7 + col. A cell is marked before it is pushed, so it
# is pushed at most once and the list never holds more than 98 cells.
# Registers: $s0 = cells in the work list, $s1 = colour, $s2 = work list base,
#            $s3 = cell being visited, $t4 = its row, $t5 = its col.
##############################################################################
flood_fill:
    addi $sp, $sp, -20          # save $ra, $s0 to $s3
    sw   $ra, 0($sp)
    sw   $s0, 4($sp)
    sw   $s1, 8($sp)
    sw   $s2, 12($sp)
    sw   $s3, 16($sp)
    move $s1, $a2               # colour to match
    li   $t0, 7
    mul  $t0, $a0, $t0
    add  $t0, $t0, $a1          # seed index = row * 7 + col
    sll  $t1, $t0, 2            # byte offset into mark
    la   $t2, mark
    add  $t2, $t2, $t1
    li   $t3, 1
    sw   $t3, 0($t2)            # mark the seed cell
    la   $s2, fstack            # base address of the work list
    sw   $t0, 0($s2)            # push the seed
    li   $s0, 1                 # the list holds one cell
ff_loop:
    beqz $s0, ff_done           # nothing left to visit: finished
    addi $s0, $s0, -1           # pop one cell
    sll  $t1, $s0, 2
    add  $t1, $t1, $s2
    lw   $s3, 0($t1)            # $s3 = its index
    li   $t0, 7
    div  $s3, $t0               # index / 7
    mflo $t4                    # row = quotient
    mfhi $t5                    # col = remainder
    li   $t6, 0                 # direction offset in bytes: 0, 4, 8, 12 (up, down, left, right)
ff_dir:
    bge  $t6, 16, ff_loop       # all four directions tried: pop the next cell
    la   $t7, dir_r
    add  $t7, $t7, $t6
    lw   $t7, 0($t7)            # row change for this direction
    add  $t7, $t4, $t7          # $t7 = neighbour row
    la   $t8, dir_c
    add  $t8, $t8, $t6
    lw   $t8, 0($t8)            # column change for this direction
    add  $t8, $t5, $t8          # $t8 = neighbour col
    addi $t6, $t6, 4            # next direction for the following pass
    bltz $t7, ff_dir            # neighbour is above the top
    bge  $t7, 14, ff_dir        # neighbour is below the bottom
    bltz $t8, ff_dir            # neighbour is left of column 0
    bge  $t8, 7, ff_dir         # neighbour is right of column 6
    li   $t0, 7
    mul  $t7, $t7, $t0
    add  $t7, $t7, $t8          # neighbour index = row * 7 + col
    sll  $t7, $t7, 2            # byte offset into grid and mark
    la   $t8, grid
    add  $t8, $t8, $t7
    lw   $t9, 0($t8)            # colour of the neighbour
    bne  $t9, $s1, ff_dir       # different colour (or empty): skip
    la   $t8, mark
    add  $t8, $t8, $t7
    lw   $t9, 0($t8)            # is it already marked?
    bnez $t9, ff_dir            # yes: skip
    li   $t9, 1
    sw   $t9, 0($t8)            # mark it
    srl  $t7, $t7, 2            # convert the byte offset back to a cell index
    sll  $t1, $s0, 2
    add  $t1, $t1, $s2
    sw   $t7, 0($t1)            # push it onto the work list
    addi $s0, $s0, 1            # the list is one longer
    j    ff_dir                 # try the next direction
ff_done:
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s0, 4($sp)
    lw   $s1, 8($sp)
    lw   $s2, 12($sp)
    lw   $s3, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

##############################################################################
# clear_marks: set every cell of the mark array (98 words) to 0.
##############################################################################
clear_marks:
    la   $t0, mark              # pointer to the current word
    li   $t1, 98                # words left to clear
cm_loop:
    beqz $t1, cm_done
    sw   $zero, 0($t0)          # clear one word
    addi $t0, $t0, 4            # next word
    addi $t1, $t1, -1
    j    cm_loop
cm_done:
    jr   $ra

##############################################################################
# delete_marked: empty every grid cell whose mark is set (98 cells).
##############################################################################
delete_marked:
    la   $t0, mark              # pointer into mark
    la   $t1, grid              # pointer into grid (same cell index)
    li   $t2, 98                # cells left to check
dm_loop:
    beqz $t2, dm_done
    lw   $t3, 0($t0)            # mark of this cell
    beqz $t3, dm_skip           # not marked: leave the bubble
    sw   $zero, 0($t1)          # marked: delete the bubble
dm_skip:
    addi $t0, $t0, 4            # next cell
    addi $t1, $t1, 4
    addi $t2, $t2, -1
    j    dm_loop
dm_done:
    jr   $ra

##############################################################################
# add_score: $a0 = points to add. Updates score, splits it into 5 decimal
# digits (score_digits) and redraws the score under PTS.
##############################################################################
add_score:
    addi $sp, $sp, -8           # save $ra and $s5 (the drawing colour)
    sw   $ra, 0($sp)
    sw   $s5, 4($sp)
    lw   $t0, score
    add  $t0, $t0, $a0          # new score
    ble  $t0, 99999, as_ok      # fits in 5 digits
    li   $t0, 99999             # otherwise cap at 99999
as_ok:
    sw   $t0, score             # save the new score
    la   $t2, score_digits
    addi $t2, $t2, 4            # start at the last digit (the ones place)
    li   $t3, 10                # divisor
    li   $t4, 5                 # digits left to store
as_digit:
    div  $t0, $t3               # score / 10
    mfhi $t5                    # remainder = this digit
    mflo $t0                    # quotient = the rest of the number
    sb   $t5, 0($t2)            # store the digit
    addi $t2, $t2, -1           # move to the next digit to the left
    addi $t4, $t4, -1
    bgtz $t4, as_digit
    lw   $s5, white             # draw in white
    li   $a0, 12                # x of the first digit
    li   $a1, 23                # y of the score row
    la   $a2, score_digits      # the 5 digit bytes
    li   $a3, 5                 # number of digits
    jal  draw_number
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s5, 4($sp)
    addi $sp, $sp, 8
    jr   $ra

##############################################################################
# update_timer: once per real second, subtract 1 from time_left and redraw it.
# When it reaches 0 print "Time's up!" and exit. Uses the system clock, so the
# countdown speed does not depend on the frame rate.
##############################################################################
update_timer:
    addi $sp, $sp, -4           # save $ra
    sw   $ra, 0($sp)
    li   $v0, 30                # syscall 30 = current time in ms (low word in $a0)
    syscall
    lw   $t0, last_time         # time of the last tick
    sub  $t1, $a0, $t0          # ms since the last tick
    blt  $t1, 1000, ut_ret      # less than a second has passed
    addi $t0, $t0, 1000         # move the tick time forward by exactly one second
    sw   $t0, last_time
    lw   $t2, time_left
    addi $t2, $t2, -1           # one second less
    sw   $t2, time_left
    jal  draw_time              # redraw the LEFT counter
    lw   $t2, time_left         # reload (draw_time changed the temporaries)
    bgtz $t2, ut_ret            # still time left
    li   $v0, 4                 # syscall 4 = print string
    la   $a0, timeup_msg        # "Time's up!"
    syscall
    li   $v0, 10                # syscall 10 = exit
    syscall
ut_ret:
    lw   $ra, 0($sp)            # restore $ra and return
    addi $sp, $sp, 4
    jr   $ra

##############################################################################
# draw_time: split time_left into 3 decimal digits (left_digits) and draw them
# in the LEFT counter. A negative time is shown as 0.
##############################################################################
draw_time:
    addi $sp, $sp, -8           # save $ra and $s5 (the drawing colour)
    sw   $ra, 0($sp)
    sw   $s5, 4($sp)
    lw   $t0, time_left
    bge  $t0, 0, dt_pos         # not negative
    li   $t0, 0                 # clamp to 0
dt_pos:
    la   $t2, left_digits
    addi $t2, $t2, 2            # start at the last digit (the ones place)
    li   $t3, 10                # divisor
    li   $t4, 3                 # digits left to store
dt_digit:
    div  $t0, $t3               # time / 10
    mfhi $t5                    # remainder = this digit
    mflo $t0                    # quotient = the rest of the number
    sb   $t5, 0($t2)            # store the digit
    addi $t2, $t2, -1           # move to the next digit to the left
    addi $t4, $t4, -1
    bgtz $t4, dt_digit
    lw   $s5, white             # draw in white
    li   $a0, 12                # x of the first digit
    li   $a1, 10                # y of the LEFT counter row
    la   $a2, left_digits       # the 3 digit bytes
    li   $a3, 3                 # number of digits
    jal  draw_number
    lw   $ra, 0($sp)            # restore registers and return
    lw   $s5, 4($sp)
    addi $sp, $sp, 8
    jr   $ra