#define DDEBUG 0
#include "ddebug.h"

#include "ngx_http_memc_util.h"

ngx_http_memc_cmd_t
ngx_http_memc_parse_cmd(u_char *data, size_t len, ngx_flag_t *is_storage_cmd)
{
    switch (len) {
        case 3:
            if (ngx_str3cmp(data, 's', 'e', 't')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_set;
            }

            if (ngx_str3cmp(data, 'a', 'd', 'd')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_add;
            }

            /*
            if (ngx_str3cmp(data, 'c', 'a', 's')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_cas;
            }
            */

            if (ngx_str3cmp(data, 'g', 'e', 't')) {
                return ngx_http_memc_cmd_get;
            }

            break;

        case 4:
            if (ngx_str4cmp(data, 'g', 'e', 't', 's')) {
                return ngx_http_memc_cmd_gets;
            }

            if (ngx_str4cmp(data, 'i', 'n', 'c', 'r')) {
                return ngx_http_memc_cmd_incr;
            }

            if (ngx_str4cmp(data, 'd', 'e', 'c', 'r')) {
                return ngx_http_memc_cmd_decr;
            }

            break;

        case 5:
            if (ngx_str5cmp(data, 's', 't', 'a', 't', 's')) {
                return ngx_http_memc_cmd_decr;
            }

            break;

        case 6:
            if (ngx_str6cmp(data, 'a', 'p', 'p', 'e', 'n', 'd')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_append;
            }

            if (ngx_str6cmp(data, 'd', 'e', 'l', 'e', 't', 'e')) {
                return ngx_http_memc_cmd_delete;
            }

            break;

        case 7:
            if (ngx_str7cmp(data, 'r', 'e', 'p', 'l', 'a', 'c', 'e')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_replace;
            }

            if (ngx_str7cmp(data, 'p', 'r', 'e', 'p', 'e', 'n', 'd')) {
                *is_storage_cmd = 1;
                return ngx_http_memc_cmd_prepend;
            }

            if (ngx_str7cmp(data, 'v', 'e', 'r', 's', 'i', 'o', 'n')) {
                return ngx_http_memc_cmd_version;
            }

            break;

        case 9:
            if (ngx_str9cmp(data, 'f', 'l', 'u', 's', 'h', '_', 'a', 'l', 'l'))
            {
                return ngx_http_memc_cmd_flush_all;
            }

            if (ngx_str9cmp(data, 'v', 'e', 'r', 'b', 'o', 's', 'i', 't', 'y'))
            {
                return ngx_http_memc_cmd_verbosity;
            }

            break;

        default:
            break;
    }

    return ngx_http_memc_cmd_unknown;
}

