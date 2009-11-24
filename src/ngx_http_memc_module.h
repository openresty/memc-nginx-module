#ifndef NGX_HTTP_MEMC_MODULE_H
#define NGX_HTTP_MEMC_MODULE_H

#include <ngx_core.h>
#include <ngx_http.h>

typedef struct {
    ngx_http_upstream_conf_t   upstream;
    ngx_int_t                  index;
} ngx_http_memc_loc_conf_t;

typedef struct {
    size_t                     rest;
    ngx_http_request_t        *request;
    ngx_str_t                  key;
} ngx_http_memc_ctx_t;

extern ngx_module_t  ngx_http_memc_module;

#define NGX_HTTP_MEMC_END   (sizeof(CRLF "END" CRLF) - 1)

#endif /* NGX_HTTP_MEMC_MODULE_H */

