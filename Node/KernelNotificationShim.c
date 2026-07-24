#include "KernelNotificationShim.h"

void btck_call_context_options_set_notifications(
    void* function,
    btck_ContextOptions* context_options,
    btck_NotificationInterfaceCallbacks notifications
) {
    typeof(&btck_context_options_set_notifications) typed_function =
        (typeof(&btck_context_options_set_notifications))function;
    typed_function(context_options, notifications);
}

void btck_call_context_options_set_validation_interface(
    void* function,
    btck_ContextOptions* context_options,
    btck_ValidationInterfaceCallbacks validation_interface
) {
    typeof(&btck_context_options_set_validation_interface) typed_function =
        (typeof(&btck_context_options_set_validation_interface))function;
    typed_function(context_options, validation_interface);
}

void btck_call_logging_set_options(
    void* function,
    btck_LoggingOptions options
) {
    typeof(&btck_logging_set_options) typed_function =
        (typeof(&btck_logging_set_options))function;
    typed_function(options);
}

void btck_call_logging_disable(
    void* function
) {
    typeof(&btck_logging_disable) typed_function = (typeof(&btck_logging_disable))function;
    typed_function();
}
