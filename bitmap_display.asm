##############################################################################
# Example: Displaying Pixels
#
# This file demonstrates how to draw pixels with different colours to the
# bitmap display.
##############################################################################

######################## Bitmap Display Configuration ########################
# - Unit width in pixels: 8
# - Unit height in pixels: 8
# - Display width in pixels: 256
# - Display height in pixels: 256
# - Base Address for Display: 0x10008000 ($gp)
##############################################################################

.data

# Display address
ADDR_DSPL: .word 0x10008000

# Colours
red:    .word 0xFF0000
green:  .word 0x00FF00
blue:   .word 0x0000FF
yellow: .word 0xFFFF00
grey:   .word 0x808080


.text
.globl main

main:
    lw $s5, grey            # colour
    li $s0, 1               # left x
    li $s1, 9               # right x   
    li $s2, 4               # top y
    li $s3, 19              # bottom y  
    
    move $s4, $s0           # copy $s4 to left x
    
top_loop:
    bgt $s4, $s1, top_done   # if current x ($s4) is greater than right x, branch to top_done, loop otherwise
    move $a0, $s4            # copy current x to $a0 (x_pixel to paint)
    move $a1, $s2            # copy top y to $a1 (y_pixel to paint)
    jal draw_pixel           # jump to link draw_pixel
    addi $s4, $s4, 1
    j top_loop
    
top_done:
    move $s4, $s2            # change current x to current y (starting with top y)
    
right_loop:
    bgt $s4, $s3, right_done
    move $a0, $s1
    move $a1, $s4
    jal draw_pixel
    addi $s4, $s4, 1
    j right_loop
right_done:

    move $s4, $s0
bottom_loop:
    bgt $s4, $s1, bottom_done
    move $a0, $s4
    move $a1, $s3
    jal draw_pixel
    addi $s4, $s4, 1
    j bottom_loop
    
bottom_done:
    move $s4, $s2
    
left_loop:
    bgt $s4, $s3, left_done
    move $a0, $s0
    move $a1, $s4
    jal draw_pixel
    addi $s4, $s4, 1
    j left_loop
    
left_done:

exit:
    li $v0, 10
    syscall

draw_pixel:
    sll $t0, $a1, 6         # shift y coordinate by 6 bits (*2^6 = 128) store to $t0
    add $t0, $t0, $a0       # add x coorindate to $t0
    sll $t0, $t0, 2         # *4 bytes since each unit is 4 bytes
    lw  $t1, ADDR_DSPL      # store start in $t1
    add $t0, $t0, $t1       # add current pixel to start to save to offset
    sw  $s5, 0($t0)         # colour grey offset from start
    jr  $ra                 # jump register
