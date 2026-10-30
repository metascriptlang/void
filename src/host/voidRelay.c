#include "voidRelay.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

typedef struct VRNode { char *msg; struct VRNode *next; } VRNode;
typedef struct { VRNode *head, *tail; pthread_mutex_t mu; } VRQueue;

static VRQueue s_toVoid   = { NULL, NULL, PTHREAD_MUTEX_INITIALIZER };
static VRQueue s_fromVoid = { NULL, NULL, PTHREAD_MUTEX_INITIALIZER };

static void vr_push(VRQueue *q, const char *json) {
	if (!json) return;
	VRNode *n = (VRNode *)malloc(sizeof(VRNode));
	if (!n) return;
	n->msg = strdup(json);
	n->next = NULL;
	pthread_mutex_lock(&q->mu);
	if (q->tail) q->tail->next = n; else q->head = n;
	q->tail = n;
	pthread_mutex_unlock(&q->mu);
}

static char *vr_pop(VRQueue *q) {
	pthread_mutex_lock(&q->mu);
	VRNode *n = q->head;
	if (n) {
		q->head = n->next;
		if (!q->head) q->tail = NULL;
	}
	pthread_mutex_unlock(&q->mu);
	if (!n) return NULL;
	char *m = n->msg;
	free(n);
	return m;
}

static bool vr_has(VRQueue *q) {
	pthread_mutex_lock(&q->mu);
	bool h = q->head != NULL;
	pthread_mutex_unlock(&q->mu);
	return h;
}

void  voidRelayPushToVoid(const char *json) { vr_push(&s_toVoid, json); }
char *voidRelayPopToVoid(void)              { return vr_pop(&s_toVoid); }
bool  voidRelayHasToVoid(void)              { return vr_has(&s_toVoid); }

void  voidRelayPushFromVoid(const char *json) { vr_push(&s_fromVoid, json); }
char *voidRelayPopFromVoid(void)              { return vr_pop(&s_fromVoid); }
bool  voidRelayHasFromVoid(void)              { return vr_has(&s_fromVoid); }

void  voidRelayFreeString(char *s) { free(s); }
