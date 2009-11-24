#ifndef NGX_HTTP_MEMC_RESPONSE_H
#define NGX_HTTP_MEMC_RESPONSE_H

#include <ngx_core.h>
#include <ngx_http.h>

ngx_int_t ngx_http_memc_process_header(ngx_http_request_t *r);

ngx_int_t ngx_http_memc_filter_init(void *data);

ngx_int_t ngx_http_memc_filter(void *data, ssize_t bytes);

#endif /* NGX_HTTP_MEMC_RESPONSE_H */

