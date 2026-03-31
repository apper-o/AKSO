#include <errno.h>
#include "rstack.h"
#include <stdio.h>
#include <stdlib.h>


typedef enum
{
    VALUE, RSTACK
} element_type_t;

typedef struct node
{
    element_type_t type;
    union
    {
        uint64_t value;
        rstack_t *rs;
    };
    struct node *next;
} node_t;

typedef struct rstack
{
    size_t reference_counter;
    node_t *top;

} rstack_t;

rstack_t *rstack_new()
{
    rstack_t *rs = malloc(sizeof(rstack_t));
    
    if(rs == nullptr)
    {
        errno = ENOMEM;
        return nullptr;
    }

    rs->reference_counter = 1;
    rs->top = nullptr;

    return rs;
}

void rstack_delete(rstack_t *rs)
{
    if(rs == nullptr)
        return;
    // Firstly, we need to decrement the reference_counter and check if it is equal to 0
    rs->reference_counter--;
    if(rs->reference_counter == 0)
    {
        // If the reference_counter is 0 then we need to delete all elements of the stack
        node_t *current = rs->top;
        while(current != nullptr)
        {
            node_t *next = current->next;
            // If the current element is a stack, we need to recursively use rstack_delete on this stack
            if(current->type == RSTACK)
                rstack_delete(current->rs);
            // After recursive function we can free the current element and move to the next element in the rstack
            free(current);
            current = next;
        }
        // At the end we can free the rstack
        free(rs);
    }
}

int rstack_push_value(rstack_t *rs, uint64_t value)
{
    // Error case: null pointer
    if(rs == nullptr)
    {
        errno = EINVAL;
        return -1;
    }

    // Error case: erroneous memory allocation
    node_t *node = malloc(sizeof(node_t));
    if(node == nullptr)
    {
        errno = ENOMEM;
        return -1;
    }

    // Updates node parameters and changes top node.
    node->next = rs->top;
    node->type = VALUE;
    node->value = value;

    rs->top = node;

    return 0;
}

int rstack_push_rstack(rstack_t *rs1, rstack_t *rs2)
{
    // Error case: null pointer
    if(rs1 == nullptr || rs2 == nullptr)
    {
        errno = ENOMEM;
        return -1;
    }

    // Error case: erroneous memory allocation
    node_t *node = malloc(sizeof(node_t));
    if(node == nullptr)
    {
        errno = ENOMEM;
        return -1;
    }

    // Updates node parameters and changes top node.
    node->next = rs1->top;
    node->type = RSTACK;
    node->value = rs2;

    rs1->top = node;

    // We need to update reference_counter for rs2
    rs2->reference_counter++;

    return 0;
}

/*
 * Pops the top element on the stack
*/
void rstack_pop(rstack_t *rs)
{
    // Error case: rs is a null pointer or rs is empty
    if(rs == nullptr || rs->top == nullptr)
        return;
    
    // We reassign the top element of the rstack
    node_t *top = rs->top;
    rs->top = top->next;

    // If top->type is a rstack we need to use rstack_delete on it.
    // In the end we free the top node
    if(top->type == RSTACK)
        rstack_delete(top->rs);
    free(top);
}

/*
 * Returns true if rstack is empty or the rstack does not have a number
 * Returns false if the rstack has a number
*/
bool rstack_empty(rstack_t *rs)
{
    if(rs == nullptr)
        return true;
    node_t *node = rs->top;
    while(node != nullptr && node->type == RSTACK)
        node = node->next;
    if(node->type == RSTACK)
        return true;
    return false;
}

/*
 * Finds the topmost number. 
 * Returns result_t where flag represents whether a value was found and value represents the value (0 if nothing was found)
*/
result_t rstack_front(rstack_t *rs)
{
    result_t result = {false, 0};
    if(rs == nullptr)
        return result;
    node_t *node = rs->top;
    while(node != nullptr && node->type == RSTACK)
        node = node->next;
    if(node != nullptr)
    {
        result.flag = true;
        result.value = 0;
    }   
    return result;
}

rstack_t* rstack_read(char const *path)
{
    if(path == nullptr)
    {
        return nullptr;
    }

    FILE *file = fopen(path, "r");
    if(file == nullptr)
    {
        // errno is set to ENOENT
        return nullptr; // ew. dodać printy do errno
    }

    fclose(file);
}


