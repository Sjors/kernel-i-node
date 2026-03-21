#ifndef KernelNotificationShim_h
#define KernelNotificationShim_h

#include <stddef.h>
#include <stdint.h>

typedef uint8_t btck_SynchronizationState;
typedef uint8_t btck_Warning;

typedef void (*btck_DestroyCallback)(void* user_data);
typedef void (*btck_NotifyBlockTip)(void* user_data, btck_SynchronizationState state, const void* entry, double verification_progress);
typedef void (*btck_NotifyHeaderTip)(void* user_data, btck_SynchronizationState state, int64_t height, int64_t timestamp, int presync);
typedef void (*btck_NotifyProgress)(void* user_data, const char* title, size_t title_len, int progress_percent, int resume_possible);
typedef void (*btck_NotifyWarningSet)(void* user_data, btck_Warning warning, const char* message, size_t message_len);
typedef void (*btck_NotifyWarningUnset)(void* user_data, btck_Warning warning);
typedef void (*btck_NotifyFlushError)(void* user_data, const char* message, size_t message_len);
typedef void (*btck_NotifyFatalError)(void* user_data, const char* message, size_t message_len);
typedef void (*btck_ValidationInterfaceBlockChecked)(void* user_data, void* block, const void* state);
typedef void (*btck_ValidationInterfacePoWValidBlock)(void* user_data, void* block, const void* entry);
typedef void (*btck_ValidationInterfaceBlockConnected)(void* user_data, void* block, const void* entry);
typedef void (*btck_ValidationInterfaceBlockDisconnected)(void* user_data, void* block, const void* entry);

typedef struct {
    void* user_data;
    btck_DestroyCallback user_data_destroy;
    btck_NotifyBlockTip block_tip;
    btck_NotifyHeaderTip header_tip;
    btck_NotifyProgress progress;
    btck_NotifyWarningSet warning_set;
    btck_NotifyWarningUnset warning_unset;
    btck_NotifyFlushError flush_error;
    btck_NotifyFatalError fatal_error;
} btck_NotificationInterfaceCallbacks;

typedef struct {
    void* user_data;
    btck_DestroyCallback user_data_destroy;
    btck_ValidationInterfaceBlockChecked block_checked;
    btck_ValidationInterfacePoWValidBlock pow_valid_block;
    btck_ValidationInterfaceBlockConnected block_connected;
    btck_ValidationInterfaceBlockDisconnected block_disconnected;
} btck_ValidationInterfaceCallbacks;

void btck_call_context_options_set_notifications(
    void* function,
    void* context_options,
    btck_NotificationInterfaceCallbacks notifications
);

void btck_call_context_options_set_validation_interface(
    void* function,
    void* context_options,
    btck_ValidationInterfaceCallbacks validation_interface
);

typedef struct {
    int log_timestamps;
    int log_time_micros;
    int log_threadnames;
    int log_sourcelocations;
    int always_print_category_levels;
} btck_LoggingOptions;

void btck_call_logging_set_options(
    void* function,
    btck_LoggingOptions options
);

void btck_call_logging_disable(
    void* function
);

#endif
