
#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                                                 @ Specify unified assembly syntax
.cpu    cortex-m0plus                                           @ Specify CPU type is Cortex M0+
.thumb                                                          @ Specify thumb assembly for RP2040
.global main_asm                                                @ Provide program starting address to the linker
.align 4                                                        @ Specify code alignment

.equ GPIO_BTN_INPT, 21
.equ    GPIO_LED_PIN, 28                                        @ Specify pin for the built-in LED
.equ    GPIO_DIR_IN,   0                                        @ Specify input direction for a GPIO pin
.equ    GPIO_DIR_OUT,  1                                        @ Specify output direction for a GPIO pin



@ Entry point to the ASM portion of the program
main_asm:
    bl    initalise_buttons                                   @ Infinite loop
    bl    create_alarm_isr
    bl    create_gpio_isr


@ settng up the button used for input.
initalise_buttons:
    push    {lr}                                                

    movs    r0, #GPIO_BTN_INPT                                            
    bl      asm_gpio_init                                      
    movs    r0, #GPIO_BTN_INPT                                             
    movs    r1, #GPIO_DIR_IN                                    
    bl      asm_gpio_set_dir                                    
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

.thumb_func
gpio_isr:
    push {lr}
    bl      watchdog_update
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
    bl      get_differnce                                       @needs c functiion
    movs    r9, r0
    bl      watchdog_update
    
    movs    r0, r9
    movs    r9, #0                                              
    cmp     r0, #DOT                                            
    blt     input_dot                                           
    bge     input_dash                                               
    b       input_complete                                           

input_dot:
    mov     r4, #1                                              
    b       input_complete

input_dash:
    mov     r4, #2                                              

input_complete:
    pop     {pc} 


@ Set data alignment
.data
    .align 4
