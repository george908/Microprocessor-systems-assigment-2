
#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                                                 @ Specify unified assembly syntax
.cpu    cortex-m0plus                                           @ Specify CPU type is Cortex M0+
.thumb                                                          @ Specify thumb assembly for RP2040
.global main_asm                                                @ Provide program starting address to the linker
.align 4                                                        @ Specify code alignment

.equ    DFLT_STATE_STRT, 1                                      @ Specify the value to begin flashing
.equ    DFLT_STATE_STOP, 0                                      @ Specify the value to stop flashing
.equ    DFLT_ALARM_TIME, 1000000                                @ Specify the default alarm timeout
.equ    SLEEP_TIME, 5000

.equ    GPIO_BTN_EN_MSK, 0x00400000                             @ Bit-22 for rising-edge event on GP21
.equ    GPIO_BTN_DN_MSK, 0x00800000                             @ Bit-23 for falling-edge event on GP21

.equ    DOT, 255                                                @ DOT = < 255ms, DASH = > 255ms
                                                                
.equ    GPIO_BTN,  21                                           @ Specify pin for the button
.equ    GPIO_LED_PIN, 28                                        @ Specify pin for the built-in LED
.equ    GPIO_DIR_IN,   0                                        @ Specify input direction for a GPIO pin
.equ    GPIO_DIR_OUT,  1                                        @ Specify output direction for a GPIO pin

.equ    GPIO_ISR_OFFSET, 0x74                                   @ GPIO is int #13 (vector table entry 29)
.equ    ALRM_ISR_OFFSET, 0x40                                   @ ALARM0 is int #0 (vector table entry 16)


@r4 = gpio interupt// 1 = "."  // 2 = "-"
@r5 = Alarm interupt// 1 = "/space/"  // 2 = "enter"
@r6 = level
@r7 = lives

@r9 = used in interupt handling for time checks

@TODO: ARM = input handling, fix the level selection and any alarm bugs
@       C = functions listed to do 

@ Entry point to the ASM portion of the program
main_asm:
    bl    initalise_buttons                                     @ Infinite loop
    bl    create_alarm_isr
    bl    create_gpio_isr

Start_game:
    mov r6, #0
    bl start_screen                     @needs c
    bl level_select                     @needs c

wait_for_level_toBe_selected:
    bl process_input                    @still needs to be set up
    cmp r6, #0
    bne wait_for_level_tobe_selected                            @loop to wait for the levels to be selected

Start:                                                          @start of game loop
    bl init_input                      @needs c
    bl get_level                       @needs c
    cmp r0, #1
    beq level1
    cmp r0, #2
    beq level2

level1:
    bl print_level1_msg                @needs c
    b level_selected    

level2:
    bl print_level2_msg                 @needs c
    b level_selected

level_selected:                                                 
    movs    r4, #3                                              @ r4 gpio interupt
    movs    r5, #0                                              @ r5 alarm interrupts
    movs    r7, #3

no_input:
    bl      new_alarm                                           @ Set the alarm
    wfi                                                         @ Wait for interrupt
    bl      store_input              @needs c  /input r4, 1= dot , 2= dash
    cmp     r4, #3                        
    beq     Skip                                  
    movs    r4, #0                                              @ Reset dot or dash

Skip:
    bl check_game_progress          @needs c  /r0// 0= complete / 1=loss/ 2=still playing
    cmp r0, #0
    beq completed                   @still needs to be done
    cmp r0, #1
    beq loser                       @restart on loss
    b no_input

loser:
    sub r7, r7, #1
    cmp r7, #0
    beq you_lost
    bl incorrect_msg                @needs c
    b no_input

you_lost:
    bl game_over_msg                @needs c
    b Start_game

completed:
    bl get_level
    cmp r0, #1
    beq level1_completed
    cmp r0, #2
    beq level2_completed

level1_completed:
    bl level_complete_msg       @ needs c
    movs r0, #2
    bl set_level
    b finish_level

level2_completed:
    bl level_complete_msg       @ needs c
    movs r0, #3
    bl set_level
    b finish_level

finish_level:
    b start









############################################################################
#                  Alarm interupts and intilisation functions              #
############################################################################
@ settng up the button used for input.
initalise_buttons:
    push    {lr}                                                

    movs    r0, #GPIO_BTN_INPT                                            
    bl      asm_gpio_init                                  @needs c    
    movs    r0, #GPIO_BTN_INPT                                             
    movs    r1, #GPIO_DIR_IN                                    
    bl      asm_gpio_set_dir                              @needs c      
    movs    r0, #GPIO_BTN_INPT                                             
    bl      asm_gpio_set_irq                                    

    pop     {pc}                 


@creating the interupt handlier
create_alarm_isr:
    ldr     r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET) 
    ldr     r1, [r2]                                            @get the address of the vector table
    movs    r2, #ALRM_ISR_OFFSET
    add     r2, r1                                              @store the new alarm handler in the vector trable
    ldr     r0, =alrm_isr
    str     r0, [r2]

    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)           @diasble the original handlier
    movs    r1, #1 
    str     r1, [r2]
    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)           @enable the new handlier
    movs    r1, #1 
    str     r1, [r2]

    bx      lr

@Alarm interupt handling
.thumb_func 
alrm_isr:
    push    {lr}                      

    ldr     r2, =(TIMER_BASE + TIMER_INTR_OFFSET)
    movs    r1, #1
    str     r1, [r2]

    cmp     r9, #0                      @ check if the buttn is still being held
    bne     gpio_interrupt_in_progress
    cmp     r4, #3
    beq     gpio_interrupt_in_progress

gpio_interrupt_in_progress:

    pop     {pc}



@Installing the button interupts to the vector table
create_gpio_isr:
    ldr     r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)              
    ldr     r1, [r2]                                            
    movs    r2, =GPIO_ISR_OFFSET                               
    add     r2, r1
    ldr     r0, =gpio_isr                           
    str     r0, [r2]                                

    ldr     r0, =0x1
    lsls    r0, #13
    ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)                    
    str     r0, [r1]            

    ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)                    
    str     r0, [r1]

    bx      lr                                                 


@gpio interupt handlier
.thumb_func
gpio_isr:
    push {lr}
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET)
    ldr     r1, [r2]
    ldr     r0, =GPIO_BTN_DN_MSK
    cmp     r0, r1
    beq     falling_edge
    ldr     r0, =GPIO_BTN_UP_MSK
    cmp     r0, r1
    beq     rising_edge
    bl      start_timer
    pop     {pc}

rising_edge: 
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)        
    ldr     r1, =GPIO_BTN_EN_MSK
    str     r1, [r2]

    bl      get_time                                            @needs c funstion
    movs    r9, r0                                              @ start time stored in r9

    b       input_complete

falling_edge:
    ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)       
    ldr     r1, =GPIO_BTN_DN_MSK
    str     r1, [r2]
    
    bl      get_time
    movs    r1, r9                                              @needs c function
    bl      get_differnce            @needs c functiion  // difference in time between r0, r1
    movs    r9, r0
    
    movs    r9, #0                                              
    cmp     r0, #DOT                                            
    blt     input_dot                                           
    bge     input_dash                                               
    b       input_complete                                           

input_dot:
    ldr     r4, =1                                               
    b       input_complete

input_dash:
    ldr     r4, =2                                               

input_complete:
    pop     {pc} 


@ Set data alignment
.data
    .align 4
