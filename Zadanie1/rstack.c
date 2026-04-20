#include "rstack.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

// Types of elements stored in the stack nodes
typedef enum { VALUE, RSTACK } element_type;

typedef struct rstack {
    size_t reference_counter; // Total references
    size_t rstack_counter;    // References from other stacks

    struct node *top;

    // For cycle detection
    size_t cycle_id;

    // Garbage Collector state and double-linked list pointers
    bool marked_gc;
    struct rstack *next_gc;
    struct rstack *prev_gc;
} rstack_t;

// Node structure representing an element in the rstack
typedef struct node {
    element_type type;
    union {
        uint64_t value;
        struct rstack *rs;
    };
    struct node *next;
} node_t;

// Structure for cycle detection in write function
typedef struct cycle_rstack {
    rstack_t *rs;
    struct cycle_rstack *next;
} cycle_rstack_t;

// Global list head for the Garbage Collector
static rstack_t *global_top = nullptr;

// Global timer used to detect cycles
static size_t cycle_timer = 0;

// Allocate and initializes a new stack, registering it for GC
rstack_t *rstack_new() {
    rstack_t *rs = malloc(sizeof(rstack_t));
    if (rs == nullptr) {
        errno = ENOMEM;
        return nullptr;
    }

    // Initialize all fields to prevent undefined behavior
    rs->reference_counter = 1;
    rs->rstack_counter = 0;
    rs->top = nullptr;
    rs->marked_gc = false;
    rs->cycle_id = 0;

    // Adjust the GC list
    rs->next_gc = global_top;
    rs->prev_gc = nullptr;
    if (global_top != nullptr)
        global_top->prev_gc = rs;
    global_top = rs;

    return rs;
}

// Recursively mark a stack and all its nested stacks to prevent deletion
void mark(rstack_t *rs) {
    if (rs == nullptr || rs->marked_gc == true)
        return;

    rs->marked_gc = true;

    node_t *node = rs->top;
    while (node != nullptr) {
        if (node->type == RSTACK)
            mark(node->rs);
        node = node->next;
    }
}

// Clean up unmarked stacks and their contents
void rstack_gc() {
    // Unmark every existing rstack
    for (rstack_t *rs = global_top; rs != nullptr; rs = rs->next_gc) {
        rs->marked_gc = false;
    }

    // Mark stacks used by the user
    for (rstack_t *rs = global_top; rs != nullptr; rs = rs->next_gc) {
        if (rs->reference_counter > rs->rstack_counter)
            mark(rs);
    }

    // Remove elements from every unmarked rstack
    for (rstack_t *rs = global_top; rs != nullptr; rs = rs->next_gc) {
        if (rs->marked_gc == false) {
            node_t *node = rs->top;
            rs->top = nullptr;
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

    // Free the memory of unmarked rstacks and update the global list
    rstack_t *rs = global_top;
    while (rs != nullptr) {
        rstack_t *next_rs = rs->next_gc;
        if (rs->marked_gc == false) {
            // Repairs double-linked list
            if (rs->prev_gc == nullptr)
                global_top = rs->next_gc;
            else
                rs->prev_gc->next_gc = rs->next_gc;

            if (rs->next_gc != nullptr)
                rs->next_gc->prev_gc = rs->prev_gc;

            free(rs);
        }
        rs = next_rs;
    }
}

// Decrease the user reference count
void rstack_delete(rstack_t *rs) {
    if (rs == nullptr)
        return;

    if (rs->reference_counter > 0)
        rs->reference_counter--;

    rstack_gc();
}

// Add a value to the rstack
int rstack_push_value(rstack_t *rs, uint64_t value) {
    if (rs == nullptr) {
        errno = EINVAL;
        return -1;
    }

    node_t *node = malloc(sizeof(node_t));
    if (node == nullptr) {
        errno = ENOMEM;
        return -1;
    }

    // Initialize the node and update the stack top
    node->type = VALUE;
    node->value = value;
    node->next = rs->top;
    rs->top = node;

    return 0;
}

// Push a pointer to another rstack (rs2) into the rstack (rs1)
int rstack_push_rstack(rstack_t *rs1, rstack_t *rs2) {
    if (rs1 == nullptr || rs2 == nullptr) {
        errno = EINVAL;
        return -1;
    }

    node_t *node = malloc(sizeof(node_t));
    if (node == nullptr) {
        errno = ENOMEM;
        return -1;
    }

    // Initialize the node as an RSTACK type
    node->type = RSTACK;
    node->rs = rs2;
    node->next = rs1->top;
    rs1->top = node;

    // Update counters:  rs2 is now referenced by rs1 internally
    rs2->reference_counter++;
    rs2->rstack_counter++;

    return 0;
}

// Remove the topmost element from the stack and update references
void rstack_pop(rstack_t *rs) {
    // Return early if the stack is null or already empty
    if (rs == nullptr || rs->top == nullptr)
        return;

    node_t *top = rs->top;
    rs->top = top->next;

    // If the detached node contained another stack, decrement its counters
    if (top->type == RSTACK) {
        top->rs->reference_counter--;
        top->rs->rstack_counter--;
        // Trigger garbage collection to clean up potentially abandoned cycles
        rstack_gc();
    }

    free(top);
}

// Helper function to check emptiness, avoiding cycles
bool recursive_empty(rstack_t *rs) {
    // A null pointer is considered empty
    if (rs == nullptr)
        return true;

    // Checks if rstack was visited in this call
    if (cycle_timer == rs->cycle_id)
        return true;
    rs->cycle_id = cycle_timer;

    node_t *node = rs->top;
    while (node != nullptr && node->type == RSTACK) {
        if (recursive_empty(node->rs) == false)
            return false;
        node = node->next;
    }

    // Only if node is not nullptr, the loop stopped at a VALUE element
    return (node == nullptr);
}

// Check if the stack is constains any VALUE node
bool rstack_empty(rstack_t *rs) {
    cycle_timer++;
    return recursive_empty(rs);
}

// Helper function to find rstack_front checking for cycles
result_t recursive_front(rstack_t *rs) {
    result_t result = {false, 0};
    // Invalid pointer
    if (rs == nullptr)
        return result;

    // Checks if rstack was visited in this call
    if (cycle_timer == rs->cycle_id)
        return result;
    rs->cycle_id = cycle_timer;

    // Checks for a number recursively
    node_t *node = rs->top;
    while (node != nullptr && node->type == RSTACK) {
        result_t current_result = recursive_front(node->rs);
        if (current_result.flag == true)
            return current_result;
        node = node->next;
    }

    // Capture the value if the current node is of type VALUE
    if (node != nullptr && node->type == VALUE) {
        result.flag = true;
        result.value = node->value;
    }

    return result;
}

// Get the first value of the rstack
result_t rstack_front(rstack_t *rs) {
    cycle_timer++;
    return recursive_front(rs);
}

// Read rstack contents from a text file.
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
    rstack_t *rs = rstack_new();
    if (rs == nullptr) {
        int saved_errno = errno; 
        fclose(f);
        errno = saved_errno;
        return nullptr;
    }

    char buffer[64];
    while (fscanf(f, "%63s", buffer) == 1) {
        // Validation: No negative signs allowed for uint64_t
        if (buffer[0] == '-') {
            int saved_errno = EINVAL;
            fclose(f);
            rstack_delete(rs);
            errno = saved_errno;
            return nullptr;
        }

        char *endptr;
        errno = 0;
        unsigned long long value = strtoull(buffer, &endptr, 10);

        // Ensure successful conversion without trailing characters
        if (errno == ERANGE || *endptr != '\0') {
            int saved_errno = (errno == ERANGE) ? ERANGE : EINVAL;
            fclose(f);
            rstack_delete(rs);
            errno = saved_errno;
            return nullptr;
        }

        if (rstack_push_value(rs, (uint64_t)value) != 0) {
            int saved_errno = errno; 
            fclose(f);
            rstack_delete(rs);
            errno = saved_errno;
            return nullptr;
        }
    }

    // Verify file reading stopped due to EOF
    if (feof(f) == false) {
        int saved_errno = errno;
        fclose(f);
        rstack_delete(rs);
        errno = saved_errno;
        return nullptr;
    }

    fclose(f);
    return rs;
}

// Helper for writing stack elements bottom-up
int recursive_write(FILE *f, node_t *node, cycle_rstack_t *top) {
    if (node == nullptr)
        return 0;

    // Use recursion to achieve bottom-up printing
    int result = recursive_write(f, node->next, top);
    if (result != 0)
        return result;

    if (node->type == VALUE) {
        if (fprintf(f, "%" PRIu64 "\n", node->value) < 0)
            return -1;
    } else {
        // Cycle detection for nested stacks
        cycle_rstack_t *cycle_rs = top;
        while (cycle_rs != nullptr && cycle_rs->rs != node->rs)
            cycle_rs = cycle_rs->next;
        if (cycle_rs != nullptr && cycle_rs->rs == node->rs)
            return 1; // Signal detected cycle

        cycle_rstack_t next_top = {node->rs, top};
        result = recursive_write(f, node->rs->top, &next_top);
        if (result != 0)
            return result;
    }
    return 0;
}

// Write the entire rstack to a file
int rstack_write(char const *path, rstack_t *rs) {
    if (path == nullptr || rs == nullptr) {
        errno = EINVAL;
        return -1;
    }

    FILE *f = fopen(path, "w");
    if (f == NULL)
        return -1;

    // Recursively writes elements to a file (bottom - up)
    cycle_rstack_t initial_top = {rs, nullptr};
    if (recursive_write(f, rs->top, &initial_top) == -1) {
        int saved_errno = errno;
        fclose(f);
        errno = saved_errno;
        return -1;
    }

    if (fclose(f) == EOF)
        return -1;

    return 0;
}

// Free memory from all rstack that haven't been manualy freed by the user
__attribute__((destructor)) static void rstack_clean(void) {
    rstack_t *rs = global_top;

    while (rs != nullptr) {
        node_t *node = rs->top;

        // Free all the elements
        while (node != nullptr) {
            node_t *next = node->next;
            free(node);
            node = next;
        }

        // Free the rstacks
        rstack_t *next_rs = rs->next_gc;
        free(rs);
        rs = next_rs;
    }

    global_top = nullptr;
}
