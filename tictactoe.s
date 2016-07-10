.bss
buffer:
    .zero 256
.data
    .align 16
field:
    .zero 16 # 9 fields actually used (the first three bytes of each word)
cursor_mask:
    .fill 16, 1, 0x08
field_mask:
    .byte 0xff, 0xff, 0xff, 0x00
    .byte 0xff, 0xff, 0xff, 0x00
    .byte 0xff, 0xff, 0xff, 0x00
    .byte 0xff, 0xff, 0xff, 0x00
display_chars:
    .ascii " xo.||\n^^^^"
current_player:
    .byte 1

.text
.global _start
_start:
    mov $1, %eax
    call set_show_cursor

    call tty_flip_raw_mode
    movb $0x08, field # initialize cursor at upper left position

main_loop:
    call print_field

    call look_for_winners
    testb $0x80, %cl
    jz finish_after_victory

    call read_stdin

    call get_free_position
    testb $0x80, %ch
    jz main_loop

after_main_loop:
    call exit

finish_after_victory:
    hlt
    jmp after_main_loop


print_field:
    xor %ebx, %ebx # y
    xor %eax, %eax # x
    mov $field, %rsi
    mov $display_chars, %rcx
    mov $buffer, %rdi

    movl $0x4a325b1b, (%rdi)  # ESC[2J, clear screen
    movl $0x48305b1b, 4(%rdi) # ESC[0H, reset cursor
    add $8, %rdi
print_field_loop:
    movzbq (%rsi), %rdx # load field value
    add $1, %rsi
    movb (%rcx, %rdx), %dl # get x/o/empty
    movb 4(%rcx, %rax), %dh # get | or newline
    mov %dx, (%rdi) # store both in buffer
    add $2, %rdi

    add $1, %eax
    cmp $3, %eax
    jne print_field_loop

    # end of current line

    add $1, %ebx
    cmp $3, %ebx
    je print_loop_done

    movl $0x2b2d2b2d,  (%rdi) # -+-+
    movl $0x00000a2d, 4(%rdi) # -\n
    add $6, %rdi
    add $1, %rsi
    xor %eax, %eax
    jmp print_field_loop

print_loop_done:
    # all data is in the buffer
    mov $buffer, %rsi
    sub %rsi, %rdi # calculate used length
    mov %rdi, %rdx
    mov $0x1, %rax # write
    mov $1, %rdi # stdout
    syscall
    ret


tty_flip_raw_mode:
    mov $0x10, %eax # ioctl
    mov $0, %rdi # stdin
    mov $0x00005401, %rsi # TCGETS
    mov $buffer, %rdx
    syscall
    xorl $0x0A, 12(%rdx) # c_cflag^(ICANON|ECHO)
    mov $0x10, %eax # ioctl
    mov $0x00005402, %rsi # TCSETS
    syscall
    ret


set_show_cursor:
    mov $buffer, %rsi

    movl $0x323f5b1b, (%rsi) # ESC[?2
    movl $0x00006835, %edx # 5h
    shl $2, %eax
    add %al, %dh # 5h -> 5l for hiding the cursor
    mov %dx, 4(%rsi)

    mov $6, %rdx
    mov $0x1, %rax # write
    mov $1, %rdi # stdout
    syscall
    ret


read_stdin:
    mov $buffer, %rsi
    mov $256, %rdx
    mov $0x0, %rdi # stdin
try_read_stdin:
    mov $0x0, %rax # read
    syscall
    cmp $0x1, %rax
    jl exit # less than 1 byte (or negative) -> just exit
    mov (%rsi), %rcx
    je read_one_byte
    cmp $0x3, %rax
    jne try_read_stdin # unknown input, read again.

    # exactly three bytes, read into rcx
    # this probably starts with ESC[
    cmp $0x5b1b, %cx
    jne try_read_stdin

    bswap %ecx # move the direction-indicating character to ch
    sub $0x41, %ch
    cmp $4, %ch
    jae try_read_stdin
    movzbl %ch, %eax
    call try_move_cursor
    ret

read_one_byte:
    cmp $0x20, %cl # ' '
    je read_space

    # exactly one byte, read into rcx (cl)
    and $0xdf, %cl # case-insensitivity
    cmp $0x51, %cl # Q
    je exit
    jmp try_read_stdin

read_space:
    call place_current_player_piece
    ret


place_current_player_piece:
    call get_cursor_position
    mov field(%ecx), %al
    test $0x3, %al
    jnz place_piece_fail

    or current_player, %al
    mov %al, field(%ecx)

    # switch players
    xorb $3, current_player
    # ret
place_piece_fail:
    ret


# returns a free position in (cl, ch). all bits will be set when none are free.
get_free_position:
    mov $-1, %edx
    movdqa field, %xmm0
    movdqa cursor_mask, %xmm1
    pandn %xmm0, %xmm1 # xmm1 := field &~ cursor_mask
    pxor %xmm0, %xmm0
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %ecx
    and $0x0777, %cx
    bsr %cx, %cx
    cmovz %edx, %ecx
    ret


# returns the winner in cl if there is one.
# if there is none, all bits will be set.
look_for_winners:
    # the offsets for valid rows/columns/diagonals are 1, 3, 4, 5
    movdqa field, %xmm1
    movdqa cursor_mask, %xmm0
    pandn %xmm1, %xmm0 # %xmm0 := field &~ cursor_mask
    movdqa field_mask, %xmm7
    movdqa %xmm0, %xmm1
    movdqa %xmm0, %xmm3
    movdqa %xmm0, %xmm4
    movdqa %xmm0, %xmm5
    pslldq $1, %xmm1 # get field shifted to the left by 1, 3, 4, 5 indices
    pslldq $3, %xmm3
    pslldq $4, %xmm4
    pslldq $5, %xmm5
    pcmpeqb %xmm0, %xmm1
    pcmpeqb %xmm0, %xmm3
    pcmpeqb %xmm0, %xmm4
    pcmpeqb %xmm0, %xmm5

    pxor %xmm6, %xmm6
    pcmpeqb %xmm0, %xmm6
    pandn %xmm7, %xmm6 # %xmm6 := equal mask &~ field_mask

    pand %xmm6, %xmm1
    pand %xmm6, %xmm3
    pand %xmm6, %xmm4
    pand %xmm6, %xmm5

    pmovmskb %xmm1, %eax
    mov %eax, %edx
    shl $1, %eax
    and %eax, %edx
    and $0x111, %edx
    jnz got_winner

    pmovmskb %xmm3, %eax
    mov %eax, %edx
    shl $3, %eax
    and %eax, %edx
    and $0x004, %edx
    jnz got_winner

    pmovmskb %xmm4, %eax
    mov %eax, %edx
    shl $4, %eax
    and %eax, %edx
    and $0x007, %edx
    jnz got_winner

    pmovmskb %xmm5, %eax
    mov %eax, %edx
    shl $5, %eax
    and %eax, %edx
    and $0x001, %edx
    jnz got_winner

    mov $-1, %ecx
    ret

got_winner:
    xor %ecx, %ecx
    bsf %edx, %eax
    mov field(%eax), %cl
    ret


# returns the cursor position in (cl, ch). may not clobber eax.
get_cursor_position:
    movdqa field, %xmm0
    pand cursor_mask, %xmm0
    pxor %xmm1, %xmm1
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %ecx
    not %cx
    bsr %cx, %cx
    jz 2 # abort
    ret


# direction is in eax
try_move_cursor:
    call get_cursor_position
    mov %ecx, %edx

    # move bits 2 and 3 of cx into ch (i.e. the y position)
    shl $6, %cx
    shr $6, %cl

    cmp $3, %eax
    je try_move_left
    cmp $2, %eax
    je try_move_right
    cmp $1, %eax
    je try_move_down
    # cmp $0, %eax
    # je try_move_up

try_move_up:
    cmp $0, %ch
    je try_move_fin
    sub $1, %ch
    jmp try_move_do

try_move_down:
    cmp $2, %ch
    je try_move_fin
    add $1, %ch
    jmp try_move_do

try_move_left:
    cmp $0, %cl
    je try_move_fin
    sub $1, %cl
    jmp try_move_do

try_move_right:
    cmp $2, %cl
    je try_move_fin
    add $1, %cl
    # jmp try_move_do

try_move_do:
    andb $0xf7, field(%edx)
    call calc_pos_cx
    orb $0x08, field(%ecx)

try_move_fin:
    ret


# turns two-dimensional (cl,ch) position into 16-byte index in ecx
calc_pos_cx:
    shl $2, %ch
    or %ch, %cl
    movzbl %cl, %ecx
    ret


exit:
    mov $0, %eax
    call set_show_cursor
    call tty_flip_raw_mode
    xor %rbx, %rbx
    mov $0xe7, %rax # exit_group
    syscall
    jmp 0
