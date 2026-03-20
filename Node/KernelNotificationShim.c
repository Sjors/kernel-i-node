#include "KernelNotificationShim.h"

typedef void (*btck_context_options_set_notifications_fn)(
    void* context_options,
    btck_NotificationInterfaceCallbacks notifications
);

void btck_call_context_options_set_notifications(
    void* function,
    void* context_options,
    btck_NotificationInterfaceCallbacks notifications
) {
    ((btck_context_options_set_notifications_fn)function)(context_options, notifications);
}
