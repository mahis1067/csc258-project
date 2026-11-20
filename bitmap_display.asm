##############################################################################
# Bitmap display: border, hardcoded LEFT / PTS, 7-segment numbers
##############################################################################
# - Unit width/height in pixels: 8
# - Display width/height in pixels: 256   (so 32 x 32 units)
# - Base Address for Display: 0x10008000 ($gp)


# pixel coordinate grid looks like the following
#    x - 0, 1, 2, 3, 4 ....
#        1
#        2
#        3
#        4
#        ^y
##############################################################################

.data
ADDR_DSPL: .word 0x10008000

grey:   .word 0x808080
dark_grey: .word 0x404040     
white:  .word 0xFFFFFF

# Table of the 4 brick colours, picked from at random (index 0-3)
palette: .word 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00   # red, green, blue, yellow

# ---------------- Game variables (change these while playing) ----------------
fill_rows:   .word 6          # how many rows of bricks are filled from the top (max 14)
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

exit:
    li $v0, 10                # syscall 10 = exit program
    syscall                   # stop execution
    
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