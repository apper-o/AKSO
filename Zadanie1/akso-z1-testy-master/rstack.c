#include "rstack.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <inttypes.h>

typedef enum { VALUE, RSTACK } element_type_t;

typedef struct node {
    element_type_t type;
    union {
        uint64_t value;
        struct rstack *rs;
    };
    struct node *next;
} node_t;

typedef struct rstack {
    size_t reference_counter; 
    size_t internal_counter;  
    node_t *top;

    // Pola Garbage Collectora
    struct rstack *next_global;
    struct rstack *prev_global;
    bool marked; 
} rstack_t;

typedef struct cycle_node {
    rstack_t *rs;
    struct cycle_node *next;
} cycle_node_t;

static rstack_t *global_head = nullptr;

static void gc_mark(rstack_t *rs) {
    if (rs == nullptr || rs->marked) return;
    
    rs->marked = true;
    node_t *current = rs->top;
    while (current != nullptr) {
        if (current->type == RSTACK) {
            gc_mark(current->rs);
        }
        current = current->next;
    }
}

static void rstack_gc() {
    for (rstack_t *curr = global_head; curr != nullptr; curr = curr->next_global) {
        curr->marked = false;
    }

    for (rstack_t *curr = global_head; curr != nullptr; curr = curr->next_global) {
        if (curr->reference_counter > curr->internal_counter) {
            gc_mark(curr);
        }
    }

    for (rstack_t *curr = global_head; curr != nullptr; curr = curr->next_global) {
        if (!curr->marked) {
            node_t *current = curr->top;
            curr->top = nullptr; 
            while (current != nullptr) {
                node_t *next = current->next;
                if (current->type == RSTACK) {
                    current->rs->reference_counter--;
                    current->rs->internal_counter--;
                }
                free(current);
                current = next;
            }
        }
    }

    rstack_t *curr = global_head;
    while (curr != nullptr) {
        rstack_t *next = curr->next_global;
        if (!curr->marked) {
            if (curr->prev_global != nullptr) curr->prev_global->next_global = next;
            else global_head = next;
            
            if (next != nullptr) next->prev_global = curr->prev_global;
            
            free(curr);
        }
        curr = next;
    }
}

rstack_t *rstack_new() {
    rstack_t *rs = malloc(sizeof(rstack_t));

    if (rs == nullptr) {
        errno = ENOMEM;
        return nullptr;
    }

    rs->reference_counter = 1;
    rs->internal_counter = 0;
    rs->top = nullptr;
    rs->marked = false;

    rs->next_global = global_head;
    rs->prev_global = nullptr;
    if (global_head != nullptr) {
        global_head->prev_global = rs;
    }
    global_head = rs;

    return rs;
}

void rstack_delete(rstack_t *rs) {
    if (rs == nullptr) return;
    
    if (rs->reference_counter > 0) {
        rs->reference_counter--;
    }
    
    rstack_gc();
}

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

    node->next = rs->top;
    node->type = VALUE;
    node->value = value;

    rs->top = node;

    return 0;
}

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

    node->next = rs1->top;
    node->type = RSTACK;
    node->rs = rs2;

    rs1->top = node;

    rs2->reference_counter++;
    rs2->internal_counter++;

    return 0;
}

void rstack_pop(rstack_t *rs) {
    if (rs == nullptr || rs->top == nullptr) return;

    node_t *top = rs->top;
    rs->top = top->next;

    if (top->type == RSTACK) {
        top->rs->reference_counter--;
        top->rs->internal_counter--;
    }
    free(top);
    
    rstack_gc();
}

static bool recursive_empty(rstack_t *rs, cycle_node_t *top) {
    if (rs == nullptr)
        return true;

    cycle_node_t *current_cycle_node = top;
    while (current_cycle_node != nullptr) {
        if (current_cycle_node->rs == rs)
            return true;
        current_cycle_node = current_cycle_node->next;
    }

    cycle_node_t next_top = {rs, top};

    node_t *current_node = rs->top;
    while (current_node != nullptr && current_node->type == RSTACK) {
        if (recursive_empty(current_node->rs, &next_top) == false)
            return false;
        current_node = current_node->next;
    }
    return (current_node == nullptr || current_node->type == RSTACK);
}

bool rstack_empty(rstack_t *rs) {
    return recursive_empty(rs, nullptr);
}

static result_t recursive_front(rstack_t *rs, cycle_node_t *top) {
    result_t result = {false, 0};
    if (rs == nullptr)
        return result;

    cycle_node_t *cycle_node = top;
    while (cycle_node != nullptr) {
        if (cycle_node->rs == rs)
            return result;
        cycle_node = cycle_node->next;
    }

    cycle_node_t next_top = {rs, top};

    node_t *current_node = rs->top;
    while (current_node != nullptr && current_node->type == RSTACK) {
        result = recursive_front(current_node->rs, &next_top);
        if (result.flag == true)
            return result;
        current_node = current_node->next;
    }
    if (current_node != nullptr) {
        result.flag = true;
        result.value = current_node->value;
    }
    return result;
}

result_t rstack_front(rstack_t *rs) {
    result_t result = {false, 0};
    if (rs == nullptr)
        return result;
    return recursive_front(rs, nullptr);
}

rstack_t *rstack_read(char const *path) {
    if (path == nullptr) {
        errno = EINVAL;
        return nullptr;
    }

    FILE *file = fopen(path, "r");
    if (file == nullptr) {
        return nullptr;
    }

    rstack_t *rs = rstack_new();
    if (rs == nullptr) {
        fclose(file);
        return nullptr;
    }

    char buffer[64];

    while (fscanf(file, "%63s", buffer) == 1) {
        if (buffer[0] == '-') {
            errno = EINVAL;
            rstack_delete(rs);
            fclose(file);
            return nullptr;
        }

        char *endptr;
        errno = 0;
        unsigned long long value = strtoull(buffer, &endptr, 10);

        if (errno == ERANGE || *endptr != '\0') {
            errno = EINVAL;
            rstack_delete(rs);
            fclose(file);
            return nullptr;
        }

        if (rstack_push_value(rs, (uint64_t)value) != 0) {
            rstack_delete(rs);
            fclose(file);
            return nullptr;
        }
    }

    if (!feof(file)) {
        errno = EINVAL;
        rstack_delete(rs);
        fclose(file);
        return nullptr;
    }

    fclose(file);
    return rs;
}

static int recursive_write(FILE *file, rstack_t *rs, cycle_node_t *top) {
    if(rs == nullptr)
        return 0;

    cycle_node_t *cycle_node = top;
    while (cycle_node != nullptr) {
        if (cycle_node->rs == rs)
            return 1;
        cycle_node = cycle_node->next;
    }

    cycle_node_t next_top = {rs, top};

    node_t *current_node = rs->top;
    while (current_node != nullptr) {
        if (current_node->type == RSTACK) {
            int type = recursive_write(file, current_node->rs, &next_top);
            if (type != 0)
                return type;
        } else {
            if (fprintf(file, "%" PRIu64 "\n", current_node->value) < 0)
                return 2;
        }
        current_node = current_node->next;
    }

    return 0;
}

int rstack_write(char const *path, rstack_t *rs) {
    if (path == nullptr || rs == nullptr) {
        errno = EINVAL;
        return -1;
    }
    FILE *file = fopen(path, "w");
    if (file == nullptr)
        return -1;

    int type = recursive_write(file, rs, nullptr);

    if (fclose(file) == EOF) {
        return -1;
    }
    
    if (type == 2) {
        return -1;
    }

    return 0;
}