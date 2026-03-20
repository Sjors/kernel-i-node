#include "KernelNotificationShim.h"

typedef void (*btck_context_options_set_notifications_fn)(
    void* context_options,
    btck_NotificationInterfaceCallbacks notifications
);
typedef void (*btck_context_options_set_validation_interface_fn)(
    void* context_options,
    btck_ValidationInterfaceCallbacks validation_interface
);

void btck_call_context_options_set_notifications(
    void* function,
    void* context_options,
    btck_NotificationInterfaceCallbacks notifications
) {
    ((btck_context_options_set_notifications_fn)function)(context_options, notifications);
}

void btck_call_context_options_set_validation_interface(
    void* function,
    void* context_options,
    btck_ValidationInterfaceCallbacks validation_interface
) {
    ((btck_context_options_set_validation_interface_fn)function)(context_options, validation_interface);
}
