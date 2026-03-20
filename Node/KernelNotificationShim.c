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

typedef void (*btck_logging_set_options_fn)(btck_LoggingOptions options);

void btck_call_logging_set_options(
    void* function,
    btck_LoggingOptions options
) {
    ((btck_logging_set_options_fn)function)(options);
}
