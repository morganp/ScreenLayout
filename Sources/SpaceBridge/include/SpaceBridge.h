#include <stdint.h>
#include <stdbool.h>
#include <ApplicationServices/ApplicationServices.h>

bool SLCanMoveWindows(void);
bool SLMoveWindowToSpace(uint32_t windowID, uint64_t spaceID);
uint64_t SLSpaceForWindow(uint32_t windowID);
uint32_t SLWindowIDForAXElement(AXUIElementRef element);
