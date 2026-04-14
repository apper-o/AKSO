#include "rstack.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

typedef enum { VALUE, RSTACK } element_type;

typedef struct rstack {
    size_t reference_counter;
    // Counts nested rstack
    size_t rstack_counter;

    struct node *top;

    // garbage collector
    bool marked_gc;

    struct rstack *next_gc;
    struct rstack *prev_gc;
} rstack_t;

typedef struct node {
    element_type type;
    union {
        uint64_t value;
        struct rstack *rs;
    };
    struct node *next;
} node_t;

// Struct used in detecting cycles
typedef struct cycle_rstack {
    rstack_t *rs;
    struct cycle_rstack *next;
} cycle_rstack_t;

// Global list that stores all created rstacks - used in grabage collector
static rstack_t *global = nullptr;

rstack_t *rstack_new() {
    rstack_t *rs = malloc(sizeof(rstack_t));

    if(global == nullptr)
        global = rs;

    if (rs == nullptr) {
        errno = ENOMEM;
        return nullptr;
    }

    rs->reference_counter = 1;
    rs->rstack_counter = 0;
    
    rs->next_gc = nullptr;
    rs->prev_gc = nullptr;

    return rs;
}

void mark(rstack_t *rs) {
    // Invalid pointer or already marked
    if (rs == nullptr || rs->marked_gc == true)
        return;

    // Marks the current rstack
    rs->marked_gc = true;

    // Checks every element of rstack and recursively marks rstacks inside
    node_t *current_node = rs->top;
    while (current_node != nullptr) {
        if (current_node->type == RSTACK)
            mark(current_node->rs);
        current_node = current_node->next;
    }
}

void rstack_gc() {
    // Unmarks every existing rstack
    for (rstack_t *current_rs = global; current_rs != nullptr;
         current_rs = current_rs->next_gc) {
        current_rs->marked_gc = false;
    }

    // Marks every rstack that cannot be deleted
    for (rstack_t *current_rs = global; current_rs != nullptr;
         current_rs = current_rs->next_gc) {
        if (current_rs->reference_counter > current_rs->rstack_counter)
            mark(current_rs);
    }

    // Removes elements from every unmarked rstack
    for (rstack_t *current_rs = global; current_rs != nullptr;
         current_rs = current_rs->next_gc) {
        if (current_rs->marked_gc == false) {
            node_t *node = current_rs->top;
            current_rs->top = nullptr;
            while (node != nullptr) {
                node_t *next_node = node->next;
                if (node->type == RSTACK) {
                    node->rs->reference_counter--;
                    node->rs->rstack_counter--;
                }
                free(node);
                node = next_node;
            }
        }
    }

    // Removes unmarked rstacks
    rstack_t *rs = global;
    while (rs != nullptr) {
        rstack_t *next_rs = rs->next_gc;
        if (rs->marked_gc == false) {
            // Repairs double-linked list
            if (rs->prev_gc == nullptr)
                global = rs->next_gc;
            else
                rs->prev_gc->next_gc = rs->next_gc;

            if (rs->next_gc != nullptr)
                rs->next_gc->prev_gc = rs->prev_gc;

            free(rs);
        }
        rs = next_rs;
    }
}

void rstack_delete(rstack_t *rs) {
    // Invalid pointer
    if (rs == nullptr)
        return;

    // First we decrease a reference counter and than check if we can free the
    // space in rstack_gc
    if (rs->reference_counter > 0)
        rs->reference_counter--;

    rstack_gc();
}

// Adds a value to rstack
int rstack_push_value(rstack_t *rs, uint64_t value) {
    // Check for nullptr error
    if (rs == nullptr) {
        errno = EINVAL;
        return -1;
    }

    // Allocates memory and check for memory error
    node_t *node = malloc(sizeof(node_t));
    if (node == nullptr) {
        errno = ENOMEM;
        return -1;
    }

    // Function was successfull - prepares node fields
    node->type = VALUE;
    node->value = value;
    node->next = rs->top;
    rs->top = node;

    return 0;
}

int rstack_push_rstack(rstack_t *rs1, rstack_t *rs2) {
    // Invalid pointers provided
    if (rs1 == nullptr || rs2 == nullptr) {
        errno = EINVAL;
        return -1;
    }

    // Erroneous memory allocation
    node_t *node = malloc(sizeof(node_t));
    if (node == nullptr) {
        errno = ENOMEM;
        return -1;
    }

    // Function was successfull = prepares node fields
    node->type = RSTACK;
    node->rs = rs2;
    node->next = rs1->top;
    rs1->top = node;

    // Updates the reference and rstack counters
    rs2->reference_counter++;
    rs2->rstack_counter++;

    return 0;
}

void rstack_pop(rstack_t *rs) {
    // Check for basic requirementst to skip
    if (rs == nullptr || rs->top == nullptr)
        return;

    // Pops the last value of the stack
    node_t *top = rs->top;
    rs->top = top->next;

    // If the top element was a rstack we need to decrement the reference
    // counters
    if (top->type == RSTACK) {
        top->rs->reference_counter--;
        top->rs->rstack_counter--;
    }

    free(top);
    // Uses rstack_gc to check if we need to remove a cycle
    rstack_gc();
}

bool recursive_empty(rstack_t *rs, cycle_rstack_t *top) {
    // Basic check - rstack is empty
    if (rs == nullptr)
        return true;

    // Checks for cycles - if a cycle is detected returns true (rstakc is empty)
    for (cycle_rstack_t *current_crs = top; current_crs != nullptr;
         current_crs = current_crs->next)
        if (current_crs->rs == rs)
            return true;

    // Prepares next top cycle_rstack to detect the cycles
    cycle_rstack_t next_top = {rs, top};

    // Checks for a value in the rstack and recursively checks in nested rstacks
    node_t *current_node = rs->top;
    while (current_node != nullptr && current_node->type == RSTACK) {
        if (recursive_empty(current_node->rs, &next_top) == false)
            return false;
        current_node = current_node->next;
    }

    // If current is nullptr than no value was found
    return (current_node == nullptr);
}

bool rstack_empty(rstack_t *rs) {
    return recursive_empty(rs, nullptr);
}

result_t recursive_front(rstack_t *rs, cycle_rstack_t *top) {
    result_t result = {false, 0};
    // Invalid pointer
    if (rs == nullptr)
        return result;

    // Checks for cycles
    for (cycle_rstack_t *current_crs = top; current_crs != nullptr;
         current_crs = current_crs->next)
        if (current_crs->rs == rs)
            return result;

    // Prepares next_top for future recursive calls
    cycle_rstack_t next_top = {rs, top};

    // Checks for a number recursively
    node_t *current_node = rs->top;
    while (current_node != nullptr && current_node->type == RSTACK) {
        result_t current_result = recursive_front(current_node->rs, &next_top);
        if (current_result.flag == true)
            return current_result;
        current_node = current_node->next;
    }

    // Checks if a value was found in the current call
    if (current_node != nullptr && current_node->type == VALUE) {
        result.flag = true;
        result.value = current_node->value;
    }

    return result;
}

result_t rstack_front(rstack_t *rs) {
    return recursive_front(rs, nullptr);
}

rstack_t *rstack_read(char const *path) {
    // Invalid path
    if (path == nullptr) {
        errno = EINVAL;
        return nullptr;
    }

    // Checks if file has oppened succesfully
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return nullptr;

    // Tries to allocate memory and returns error if it was not successful
    rstack_t *rs = malloc(sizeof(rstack_t));
    if (rs == nullptr) {
        fclose(f);
        errno = ENOMEM;
        return nullptr;
    }

    char buffer[64];

    while (fscanf(f, "%63s", buffer) == 1) {
        // Negative numbers can't be an element of a rstack
        if (buffer[0] == '-') {
            errno = EINVAL;
            fclose(f);
            rstack_delete(rs);
            return nullptr;
        }

        char *endptr;
        errno = 0;

        // Converts char array to a unsigned long long and checks for potential
        // errors such as too large number or letters
        unsigned long long value = strtoull(buffer, &endptr, 10);
        if (errno == ERANGE || *endptr != '\0') {
            fclose(f);
            rstack_delete(rs);
        }

        // Tries to adda a value
        if (rstack_push_value(rs, (uint64_t)value) != 0) {
            errno = EINVAL;
            fclose(f);
            rstack_delete(rs);
        }
    }

    // Checks if all file has been read
    if (feof(f) == false) {
        fclose(f);
        rstack_delete(rs);
        return nullptr;
    }

    fclose(f);
    return rs;
}

int recursive_write(FILE *f, node_t *node, cycle_rstack_t *top) {
    // Basic case
    if(node == nullptr)
        return 0;
    
    int result = recursive_write(f, node->next, top);
    if(result != 0)
        return result;

    // If a current node type is a value then we simply print it
    // else we need to check for a cycle - if a cycle is detected we stop printing
    if (node->type == VALUE) {
        if(fprintf(f, "%" PRIu64 "\n", node->value) < 0)
            return -1;
    }
    else {
        // Checks for a cycle
        cycle_rstack_t *cycle_rs = top;
        while(cycle_rs != nullptr && cycle_rs->rs != node->rs)
            cycle_rs = cycle_rs->next;
        if(cycle_rs != nullptr && cycle_rs->rs == node->rs)
            return 1;

        cycle_rstack_t next_top = {node->rs, top};
        result = recursive_write(f, node->rs->top, &next_top);
        if(result != 0)
            return result;
    }
    return 0;
}

int rstack_write(char const *path, rstack_t *rs) {
    // Checks for invalid input
    if (path == nullptr || rs == nullptr) {
        errno = EINVAL;
        return -1;
    }

    // Tries to open a file
    FILE *f = fopen(path, "w");
    if (f == NULL)
        return -1;

    // Recursively writes elements to a file (bottom - up)
    cycle_rstack_t initial_top = {rs, nullptr};
    recursive_write(f, rs->top, &initial_top);

    fclose(f);

    return 0;
}


// Frees memory from all rstack that havent been manualy freed by the user
__attribute__((destructor)) static void rstack_clean(void) {
    rstack_t *rs = global;

    while (rs != nullptr) {
        node_t *node = rs->top;

        // First we free all the elements
        while (node != nullptr) {
            node_t *next = node->next;
            free(node);
            node = next;
        }

        // Then we can free the current rstack
        rstack_t *next_rs = rs->next_gc;
        free(rs);
        rs = next_rs;
    }

    global = nullptr;
}
