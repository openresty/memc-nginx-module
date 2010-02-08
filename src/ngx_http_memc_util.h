#ifndef NGX_HTTP_MEMC_UTIL_H
#define NGX_HTTP_MEMC_UTIL_H

#include <ngx_core.h>
#include <ngx_http.h>
#include "ngx_http_memc_module.h"

#ifndef NGX_UINT32_LEN
#define NGX_UINT32_LEN (NGX_INT32_LEN - 1)
#endif

#ifndef NGX_UINT64_LEN
#define NGX_UINT64_LEN (NGX_INT64_LEN - 1)
#endif

#ifndef ngx_str3cmp

#  define ngx_str3cmp(m, c0, c1, c2)                                       \
    m[0] == c0 && m[1] == c1 && m[2] == c2

#endif /* ngx_str3cmp */


#ifndef ngx_str4cmp

#  if (NGX_HAVE_LITTLE_ENDIAN && NGX_HAVE_NONALIGNED)

#    define ngx_str4cmp(m, c0, c1, c2, c3)                                        \
    *(uint32_t *) m == ((c3 << 24) | (c2 << 16) | (c1 << 8) | c0)

#  else

#    define ngx_str4cmp(m, c0, c1, c2, c3)                                        \
    m[0] == c0 && m[1] == c1 && m[2] == c2 && m[3] == c3

#  endif

#endif /* ngx_str4cmp */


#ifndef ngx_str5cmp

#  if (NGX_HAVE_LITTLE_ENDIAN && NGX_HAVE_NONALIGNED)

#    define ngx_str5cmp(m, c0, c1, c2, c3, c4)                                    \
    *(uint32_t *) m == ((c3 << 24) | (c2 << 16) | (c1 << 8) | c0)             \
        && m[4] == c4

#  else

#    define ngx_str5cmp(m, c0, c1, c2, c3, c4)                                    \
    m[0] == c0 && m[1] == c1 && m[2] == c2 && m[3] == c3 && m[4] == c4

#  endif

#endif /* ngx_str5cmp */


#ifndef ngx_str6cmp

#  if (NGX_HAVE_LITTLE_ENDIAN && NGX_HAVE_NONALIGNED)

#    define ngx_str6cmp(m, c0, c1, c2, c3, c4, c5)                                \
    *(uint32_t *) m == ((c3 << 24) | (c2 << 16) | (c1 << 8) | c0)             \
        && (((uint32_t *) m)[1] & 0xffff) == ((c5 << 8) | c4)

#  else

#    define ngx_str6cmp(m, c0, c1, c2, c3, c4, c5)                                \
    m[0] == c0 && m[1] == c1 && m[2] == c2 && m[3] == c3                      \
        && m[4] == c4 && m[5] == c5

#  endif

#endif /* ngx_str6cmp */


#ifndef ngx_str7cmp

#  define ngx_str7cmp(m, c0, c1, c2, c3, c4, c5, c6)                          \
    m[0] == c0 && m[1] == c1 && m[2] == c2 && m[3] == c3                      \
        && m[4] == c4 && m[5] == c5 && m[6] == c6

#endif /* ngx_str7cmp */


#ifndef ngx_str9cmp

#  if (NGX_HAVE_LITTLE_ENDIAN && NGX_HAVE_NONALIGNED)

#    define ngx_str9cmp(m, c0, c1, c2, c3, c4, c5, c6, c7, c8)                    \
    *(uint32_t *) m == ((c3 << 24) | (c2 << 16) | (c1 << 8) | c0)             \
        && ((uint32_t *) m)[1] == ((c7 << 24) | (c6 << 16) | (c5 << 8) | c4)  \
        && m[8] == c8

#  else

#    define ngx_str9cmp(m, c0, c1, c2, c3, c4, c5, c6, c7, c8)                    \
    m[0] == c0 && m[1] == c1 && m[2] == c2 && m[3] == c3                      \
        && m[4] == c4 && m[5] == c5 && m[6] == c6 && m[7] == c7 && m[8] == c8

#  endif


#endif /* ngx_str9cmp */

ngx_http_memc_cmd_t ngx_http_memc_parse_cmd(u_char *data, size_t len,
        ngx_flag_t *is_storage_cmd);

ngx_http_upstream_srv_conf_t * ngx_http_memc_upstream_add(
        ngx_http_request_t *r, ngx_url_t *url);


#endif /* NGX_HTTP_MEMC_UTIL_H */

