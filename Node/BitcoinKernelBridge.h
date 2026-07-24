#ifndef BitcoinKernelBridge_h
#define BitcoinKernelBridge_h

#include <kernel/bitcoinkernel.h>

// C enum constants are not imported as Swift values, so expose the constants
// used by the app through type-preserving inline functions.
#define BTCK_SWIFT_CONSTANT(constant) \
    static inline __typeof__(constant) btck_swift_##constant(void) \
    { \
        return constant; \
    }

BTCK_SWIFT_CONSTANT(btck_BlockCheckFlags_ALL)
BTCK_SWIFT_CONSTANT(btck_ChainType_SIGNET)
BTCK_SWIFT_CONSTANT(btck_LogCategory_ALL)
BTCK_SWIFT_CONSTANT(btck_LogLevel_DEBUG)
BTCK_SWIFT_CONSTANT(btck_LogLevel_INFO)
BTCK_SWIFT_CONSTANT(btck_ScriptVerificationFlags_ALL)
BTCK_SWIFT_CONSTANT(btck_ScriptVerifyStatus_OK)
BTCK_SWIFT_CONSTANT(btck_SynchronizationState_INIT_DOWNLOAD)
BTCK_SWIFT_CONSTANT(btck_SynchronizationState_INIT_REINDEX)
BTCK_SWIFT_CONSTANT(btck_SynchronizationState_POST_INIT)
BTCK_SWIFT_CONSTANT(btck_TxValidationResult_UNSET)
BTCK_SWIFT_CONSTANT(btck_ValidationMode_INTERNAL_ERROR)
BTCK_SWIFT_CONSTANT(btck_ValidationMode_INVALID)
BTCK_SWIFT_CONSTANT(btck_ValidationMode_VALID)
BTCK_SWIFT_CONSTANT(btck_Warning_LARGE_WORK_INVALID_CHAIN)
BTCK_SWIFT_CONSTANT(btck_Warning_UNKNOWN_NEW_RULES_ACTIVATED)

#undef BTCK_SWIFT_CONSTANT

#endif
