#include "storeIdentity.h"
#include "../../deps/sokol/sokol_gfx.h"

int32_t storeViewLive(uint32_t view) {
	return sg_query_view_state((sg_view){.id = view}) == SG_RESOURCESTATE_VALID;
}

int32_t storeBufferLive(uint32_t buffer) {
	return sg_query_buffer_state((sg_buffer){.id = buffer}) == SG_RESOURCESTATE_VALID;
}
