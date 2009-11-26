#define DDEBUG 1
#include "ddebug.h"

/*
 * Copyright (C) Igor Sysoev
 */

/*
 * Copyright (C) agentzh (章亦春)
 */

#include "ngx_http_memc_module.h"
#include "ngx_http_memc_request.h"
#include "ngx_http_memc_response.h"
#include "ngx_http_memc_util.h"

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>

static ngx_str_t  ngx_http_memc_key = ngx_string("memc_key");
static ngx_str_t  ngx_http_memc_cmd = ngx_string("memc_cmd");
static ngx_str_t  ngx_http_memc_value = ngx_string("memc_value");

static ngx_http_memc_cmd_t ngx_http_memc_parse_cmd(u_char *data, size_t len,
        ngx_flag_t *is_storage_cmd);

static ngx_int_t ngx_http_memc_reinit_request(ngx_http_request_t *r);
static void ngx_http_memc_abort_request(ngx_http_request_t *r);
static void ngx_http_memc_finalize_request(ngx_http_request_t *r,
    ngx_int_t rc);

static void *ngx_http_memc_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_memc_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

static char *ngx_http_memc_pass(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static char *ngx_http_memc_upstream_max_fails_unsupported(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static char *ngx_http_memc_upstream_fail_timeout_unsupported(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);


static ngx_conf_bitmask_t  ngx_http_memc_next_upstream_masks[] = {
    { ngx_string("error"), NGX_HTTP_UPSTREAM_FT_ERROR },
    { ngx_string("timeout"), NGX_HTTP_UPSTREAM_FT_TIMEOUT },
    { ngx_string("invalid_response"), NGX_HTTP_UPSTREAM_FT_INVALID_HEADER },
    { ngx_string("not_found"), NGX_HTTP_UPSTREAM_FT_HTTP_404 },
    { ngx_string("off"), NGX_HTTP_UPSTREAM_FT_OFF },
    { ngx_null_string, 0 }
};


static ngx_command_t  ngx_http_memc_commands[] = {

    { ngx_string("memc_pass"),
      NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
      ngx_http_memc_pass,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

#if defined(nginx_version) && nginx_version >= 8022

    { ngx_string("memc_bind"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_upsteam_bind_set_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.local),
      NULL },

#endif

    { ngx_string("memc_connect_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.connect_timeout),
      NULL },

    { ngx_string("memc_send_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.send_timeout),
      NULL },

    { ngx_string("memc_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.buffer_size),
      NULL },

    { ngx_string("memc_read_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_conf_set_msec_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.read_timeout),
      NULL },

    { ngx_string("memc_next_upstream"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_memc_loc_conf_t, upstream.next_upstream),
      &ngx_http_memc_next_upstream_masks },

    { ngx_string("memc_upstream_max_fails"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_memc_upstream_max_fails_unsupported,
      0,
      0,
      NULL },

    { ngx_string("memc_upstream_fail_timeout"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_memc_upstream_fail_timeout_unsupported,
      0,
      0,
      NULL },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_memc_module_ctx = {
    NULL,                                  /* preconfiguration */
    NULL,                                  /* postconfiguration */

    NULL,                                  /* create main configuration */
    NULL,                                  /* init main configuration */

    NULL,                                  /* create server configuration */
    NULL,                                  /* merge server configuration */

    ngx_http_memc_create_loc_conf,    /* create location configration */
    ngx_http_memc_merge_loc_conf      /* merge location configration */
};


ngx_module_t  ngx_http_memc_module = {
    NGX_MODULE_V1,
    &ngx_http_memc_module_ctx,        /* module context */
    ngx_http_memc_commands,           /* module directives */
    NGX_HTTP_MODULE,                       /* module type */
    NULL,                                  /* init master */
    NULL,                                  /* init module */
    NULL,                                  /* init process */
    NULL,                                  /* init thread */
    NULL,                                  /* exit thread */
    NULL,                                  /* exit process */
    NULL,                                  /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_memc_handler(ngx_http_request_t *r)
{
    ngx_int_t                       rc;
    ngx_http_upstream_t            *u;
    ngx_http_memc_ctx_t            *ctx;
    ngx_http_memc_loc_conf_t       *mlcf;
    /* ngx_int_t                       index; */
    ngx_http_variable_value_t      *vv;
    ngx_uint_t                      hash_key;
    ngx_http_memc_cmd_t             memc_cmd;
    ngx_flag_t                      is_storage_cmd = 0;

    hash_key = ngx_hash_key(ngx_http_memc_cmd.data, ngx_http_memc_cmd.len);

    vv = ngx_http_get_variable(r, &ngx_http_memc_cmd, hash_key, 1);
    if (vv == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (vv->not_found) {
        dd("variable $memc_cmd not found");
        vv->not_found = 0;
        vv->valid = 1;
        vv->no_cacheable = 0;

        if (r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD)) {
            vv->len = sizeof("get") - 1;
            vv->data = (u_char*) "get";
            memc_cmd = ngx_http_memc_cmd_get;

        } else if (r->method == NGX_HTTP_POST) {
            vv->len = sizeof("add") - 1;
            vv->data = (u_char*) "add";
            memc_cmd = ngx_http_memc_cmd_add;
            is_storage_cmd = 1;

        } else if (r->method == NGX_HTTP_PUT) {
            vv->len = sizeof("set") - 1;
            vv->data = (u_char*) "set";
            memc_cmd = ngx_http_memc_cmd_set;
            is_storage_cmd = 1;

        } else if (r->method == NGX_HTTP_DELETE) {
            vv->len = sizeof("delete") - 1;
            vv->data = (u_char*) "delete";
            memc_cmd = ngx_http_memc_cmd_delete;

        } else {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
             "ngx_memc: $memc_cmd variable requires explicit "
             "assignment for HTTP request method %V",
             &r->method_name);

            return NGX_HTTP_BAD_REQUEST;
        }
    } else {
        memc_cmd = ngx_http_memc_parse_cmd(vv->data, vv->len, &is_storage_cmd);

        if (memc_cmd == ngx_http_memc_cmd_unknown) {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
             "ngx_memc: unknown $memc_cmd \"%v\"", vv);

            return NGX_HTTP_BAD_REQUEST;
        }
    }

    if (ngx_http_set_content_type(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (ngx_http_upstream_create(r) != NGX_OK) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u = r->upstream;

    u->schema.len = sizeof("memcached://") - 1;
    u->schema.data = (u_char *) "memcached://";

    u->output.tag = (ngx_buf_tag_t) &ngx_http_memc_module;

    mlcf = ngx_http_get_module_loc_conf(r, ngx_http_memc_module);

    u->conf = &mlcf->upstream;

    ctx = ngx_palloc(r->pool, sizeof(ngx_http_memc_ctx_t));
    if (ctx == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ctx->memc_value_vv = NULL;
    ctx->parser_state = NGX_ERROR;

    ctx->rest = NGX_HTTP_MEMC_END;
    ctx->request = r;

    ctx->cmd_str.data = vv->data;
    ctx->cmd_str.len  = vv->len;

    ctx->cmd = memc_cmd;

    ngx_http_set_ctx(r, ctx, ngx_http_memc_module);

    if (is_storage_cmd) {
        u->create_request = ngx_http_memc_create_storage_cmd_request;
        u->process_header = ngx_http_memc_process_storage_cmd_header;

        u->input_filter_init = ngx_http_memc_empty_filter_init;
        u->input_filter = ngx_http_memc_empty_filter;

    } else if (memc_cmd == ngx_http_memc_cmd_get) {
        u->create_request = ngx_http_memc_create_get_cmd_request;
        u->process_header = ngx_http_memc_process_get_cmd_header;

        u->input_filter_init = ngx_http_memc_get_cmd_filter_init;
        u->input_filter = ngx_http_memc_get_cmd_filter;

    } else if (memc_cmd == ngx_http_memc_cmd_flush_all) {
        u->create_request = ngx_http_memc_create_noarg_cmd_request;
        u->process_header = ngx_http_memc_process_flush_all_cmd_header;

        u->input_filter_init = ngx_http_memc_empty_filter_init;
        u->input_filter = ngx_http_memc_empty_filter;

    } else {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
            "assertion failed: command \"%V\" does not have proper "
            "handlers.", &memc_cmd);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u->reinit_request = ngx_http_memc_reinit_request;
    u->abort_request = ngx_http_memc_abort_request;
    u->finalize_request = ngx_http_memc_finalize_request;

    u->input_filter_ctx = ctx;

#if defined(nginx_version) && nginx_version >= 8011

    r->main->count++;

#endif

    if (is_storage_cmd || memc_cmd == ngx_http_memc_cmd_incr
                || memc_cmd == ngx_http_memc_cmd_decr
                || memc_cmd == ngx_http_memc_cmd_verbosity)
    {
        hash_key = ngx_hash_key(ngx_http_memc_value.data, ngx_http_memc_value.len);

        vv = ngx_http_get_variable(r, &ngx_http_memc_value, hash_key, 1);
        if (vv == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ctx->memc_value_vv = vv;

        if (vv->not_found) {
            if (r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD)) {
                ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                 "ngx_memc: $memc_value variable requires explicit "
                 "assignment for HTTP request method %V and memcached "
                 "command %V",
                 &r->method_name, &ctx->cmd_str);

                return NGX_HTTP_BAD_REQUEST;

            }

            rc = ngx_http_read_client_request_body(r, ngx_http_upstream_init);

            if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
                return rc;
            }

            return NGX_DONE;
        }
    }

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    ngx_http_upstream_init(r);

    return NGX_DONE;
}


static ngx_int_t
ngx_http_memc_reinit_request(ngx_http_request_t *r)
{
    return NGX_OK;
}


static void
ngx_http_memc_abort_request(ngx_http_request_t *r)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "abort http memcached request");
    return;
}


static void
ngx_http_memc_finalize_request(ngx_http_request_t *r, ngx_int_t rc)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize http memcached request");
    return;
}


static void *
ngx_http_memc_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_memc_loc_conf_t  *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_memc_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->upstream.bufs.num = 0;
     *     conf->upstream.next_upstream = 0;
     *     conf->upstream.temp_path = NULL;
     *     conf->upstream.uri = { 0, NULL };
     *     conf->upstream.location = NULL;
     */

    conf->upstream.connect_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.send_timeout = NGX_CONF_UNSET_MSEC;
    conf->upstream.read_timeout = NGX_CONF_UNSET_MSEC;

    conf->upstream.buffer_size = NGX_CONF_UNSET_SIZE;

    /* the hardcoded values */
    conf->upstream.cyclic_temp_file = 0;
    conf->upstream.buffering = 0;
    conf->upstream.ignore_client_abort = 0;
    conf->upstream.send_lowat = 0;
    conf->upstream.bufs.num = 0;
    conf->upstream.busy_buffers_size = 0;
    conf->upstream.max_temp_file_size = 0;
    conf->upstream.temp_file_write_size = 0;
    conf->upstream.intercept_errors = 1;
    conf->upstream.intercept_404 = 1;
    conf->upstream.pass_request_headers = 0;
    conf->upstream.pass_request_body = 0;

    conf->key_var_index = NGX_CONF_UNSET;

    return conf;
}


static char *
ngx_http_memc_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_memc_loc_conf_t *prev = parent;
    ngx_http_memc_loc_conf_t *conf = child;

    ngx_conf_merge_msec_value(conf->upstream.connect_timeout,
                              prev->upstream.connect_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.send_timeout,
                              prev->upstream.send_timeout, 60000);

    ngx_conf_merge_msec_value(conf->upstream.read_timeout,
                              prev->upstream.read_timeout, 60000);

    ngx_conf_merge_size_value(conf->upstream.buffer_size,
                              prev->upstream.buffer_size,
                              (size_t) ngx_pagesize);

    ngx_conf_merge_bitmask_value(conf->upstream.next_upstream,
                              prev->upstream.next_upstream,
                              (NGX_CONF_BITMASK_SET
                               |NGX_HTTP_UPSTREAM_FT_ERROR
                               |NGX_HTTP_UPSTREAM_FT_TIMEOUT));

    if (conf->upstream.next_upstream & NGX_HTTP_UPSTREAM_FT_OFF) {
        conf->upstream.next_upstream = NGX_CONF_BITMASK_SET
                                       |NGX_HTTP_UPSTREAM_FT_OFF;
    }

    if (conf->upstream.upstream == NULL) {
        conf->upstream.upstream = prev->upstream.upstream;
    }

    if (conf->key_var_index == NGX_CONF_UNSET) {
        conf->key_var_index = prev->key_var_index;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_memc_pass(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_memc_loc_conf_t *mlcf = conf;

    ngx_str_t                 *value;
    ngx_url_t                  u;
    ngx_http_core_loc_conf_t  *clcf;

    if (mlcf->upstream.upstream) {
        return "is duplicate";
    }

    value = cf->args->elts;

    ngx_memzero(&u, sizeof(ngx_url_t));

    u.url = value[1];
    u.no_resolve = 1;

    mlcf->upstream.upstream = ngx_http_upstream_add(cf, &u, 0);
    if (mlcf->upstream.upstream == NULL) {
        return NGX_CONF_ERROR;
    }

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);

    clcf->handler = ngx_http_memc_handler;

    if (clcf->name.data[clcf->name.len - 1] == '/') {
        clcf->auto_redirect = 1;
    }

    mlcf->key_var_index = ngx_http_get_variable_index(cf, &ngx_http_memc_key);

    if (mlcf->key_var_index == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static char *
ngx_http_memc_upstream_max_fails_unsupported(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
         "\"memc_upstream_max_fails\" is not supported, "
         "use the \"max_fails\" parameter of the \"server\" directive ",
         "inside the \"upstream\" block");

    return NGX_CONF_ERROR;
}


static char *
ngx_http_memc_upstream_fail_timeout_unsupported(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
         "\"memc_upstream_fail_timeout\" is not supported, "
         "use the \"fail_timeout\" parameter of the \"server\" directive ",
         "inside the \"upstream\" block");

    return NGX_CONF_ERROR;
}


static ngx_http_memc_cmd_t
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

