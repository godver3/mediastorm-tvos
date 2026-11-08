#pragma once

#include <stdint.h>

const char *iroh_ios_bridge_version(void);
uint32_t iroh_ios_bridge_smoke_value(void);
char *iroh_ios_bridge_speed_test(const char *invite, uint64_t bytes);
char *iroh_ios_bridge_start_proxy(const char *invite);
char *iroh_ios_bridge_invalidate_proxy(void);
char *iroh_ios_bridge_start_lan_gateway(
    const char *invite,
    const char *upstream_credential,
    const char *playback_scope_json,
    double ttl_seconds,
    double expected_duration_seconds);
void iroh_ios_bridge_invalidate_lan_gateway(void);
uint64_t iroh_ios_bridge_lan_gateway_generation(void);
uint8_t iroh_ios_bridge_invalidate_lan_gateway_generation(uint64_t expected_generation);
uint64_t iroh_ios_bridge_lan_gateway_bytes(void);
char *iroh_ios_bridge_stop_lan_gateway(void);
char *iroh_ios_bridge_network_change(void);
char *iroh_ios_bridge_get_path_diagnostics(void);
char *iroh_ios_bridge_dlna_discovery_interfaces(void);
char *iroh_ios_bridge_dlna_discover(
    const char *local_ip,
    uint32_t prefix,
    uint64_t timeout_ms);
char *iroh_ios_bridge_dlna_unicast_probe(
    const char *target,
    const char *local_ip,
    uint32_t prefix);
char *iroh_ios_bridge_dlna_add_description(
    const char *description_url,
    const char *local_ip,
    uint32_t prefix);
char *iroh_ios_bridge_dlna_list_renderers(void);
char *iroh_ios_bridge_dlna_remove_renderer(const char *renderer_id);
char *iroh_ios_bridge_dlna_clear_renderers(void);
char *iroh_ios_bridge_dlna_capabilities(const char *renderer_id);
char *iroh_ios_bridge_dlna_negotiate(
    const char *renderer_id,
    const char *candidates_json,
    const char *title);
char *iroh_ios_bridge_dlna_set_uri(
    const char *renderer_id,
    const char *uri,
    const char *metadata);
char *iroh_ios_bridge_dlna_play(const char *renderer_id);
char *iroh_ios_bridge_dlna_pause(const char *renderer_id);
char *iroh_ios_bridge_dlna_stop(const char *renderer_id);
char *iroh_ios_bridge_dlna_seek(const char *renderer_id, const char *target);
char *iroh_ios_bridge_dlna_set_next(
    const char *renderer_id,
    const char *uri,
    const char *metadata);
char *iroh_ios_bridge_dlna_status(const char *renderer_id);

/* Cast sender. Replaces the Play Services Cast SDK, which sandboxed Play on
 * de-Googled Android does not provide. Every function returns a heap JSON string
 * the caller must release with iroh_ios_bridge_free_string, shaped either
 * {"ok":true,...} or {"ok":false,"code":...,"error":...}. */
char *iroh_ios_bridge_cast_discovery_interfaces(void);
char *iroh_ios_bridge_cast_discover(
    const char *local_ip,
    uint32_t prefix,
    uint64_t timeout_ms);
char *iroh_ios_bridge_cast_probe(
    const char *target,
    const char *local_ip,
    uint32_t prefix,
    uint64_t timeout_ms);
char *iroh_ios_bridge_cast_add_device(const char *address, uint32_t port);
char *iroh_ios_bridge_cast_list_devices(void);
char *iroh_ios_bridge_cast_launch(const char *device_id, const char *app_id);
char *iroh_ios_bridge_cast_load(const char *device_id, const char *media_json);
char *iroh_ios_bridge_cast_seek(const char *device_id, double position_seconds);
char *iroh_ios_bridge_cast_play(const char *device_id);
char *iroh_ios_bridge_cast_pause(const char *device_id);
char *iroh_ios_bridge_cast_stop_media(const char *device_id);
char *iroh_ios_bridge_cast_status(const char *device_id);
char *iroh_ios_bridge_cast_receiver_status(const char *device_id);
char *iroh_ios_bridge_cast_stop_session(const char *device_id);
char *iroh_ios_bridge_cast_disconnect(const char *device_id);
char *iroh_ios_bridge_resolve_code(const char *code);
void iroh_ios_bridge_free_string(char *value);
