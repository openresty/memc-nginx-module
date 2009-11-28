#define DDEBUG 0
#include "ddebug.h"

#include "ngx_http_memc_handler.h"
#include "ngx_http_memc_module.h"
#include "ngx_http_memc_request.h"
#include "ngx_http_memc_response.h"
#include "ngx_http_memc_util.h"

static ngx_str_t  ngx_http_memc_key = ngx_string("memc_key");
static ngx_str_t  ngx_http_memc_cmd = ngx_string("memc_cmd");
static ngx_str_t  ngx_http_memc_value = ngx_string("memc_value");
static ngx_str_t  ngx_http_memc_flags = ngx_string("memc_flags");


static ngx_flag_t ngx_http_memc_in_cmds_allowed(ngx_http_memc_loc_conf_t *mlcf,
        ngx_http_memc_cmd_t memc_cmd);

static ngx_int_t ngx_http_memc_reinit_request(ngx_http_request_t *r);
static void ngx_http_memc_abort_request(ngx_http_request_t *r);
static void ngx_http_memc_finalize_request(ngx_http_request_t *r,
    ngx_int_t rc);


ngx_int_t
ngx_http_memc_handler(ngx_http_request_t *r)
{
    ngx_int_t                       rc;
    ngx_http_upstream_t            *u;
    ngx_http_memc_ctx_t            *ctx;
    ngx_http_memc_loc_conf_t       *mlcf;
    /* ngx_int_t                       index; */

    ngx_http_variable_value_t      *cmd_vv;
    ngx_http_variable_value_t      *key_vv;
    ngx_http_variable_value_t      *value_vv;
    ngx_http_variable_value_t      *flags_vv;

    ngx_uint_t                      hash_key;
    ngx_http_memc_cmd_t             memc_cmd;
    ngx_flag_t                      is_storage_cmd = 0;

    hash_key = ngx_hash_key(ngx_http_memc_key.data, ngx_http_memc_key.len);

    key_vv = ngx_http_get_variable(r, &ngx_http_memc_key, hash_key, 1);

    if (key_vv == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    hash_key = ngx_hash_key(ngx_http_memc_cmd.data, ngx_http_memc_cmd.len);

    cmd_vv = ngx_http_get_variable(r, &ngx_http_memc_cmd, hash_key, 1);

    if (cmd_vv == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (cmd_vv->not_found || cmd_vv->len == 0) {
        dd("variable $memc_cmd not found");
        cmd_vv->not_found = 0;
        cmd_vv->valid = 1;
        cmd_vv->no_cacheable = 0;

        if (r->method & (NGX_HTTP_GET|NGX_HTTP_HEAD)) {
            cmd_vv->len = sizeof("get") - 1;
            cmd_vv->data = (u_char*) "get";
            memc_cmd = ngx_http_memc_cmd_get;

        } else if (r->method == NGX_HTTP_POST) {
            cmd_vv->len = sizeof("add") - 1;
            cmd_vv->data = (u_char*) "add";
            memc_cmd = ngx_http_memc_cmd_add;
            is_storage_cmd = 1;

        } else if (r->method == NGX_HTTP_PUT) {
            cmd_vv->len = sizeof("set") - 1;
            cmd_vv->data = (u_char*) "set";
            memc_cmd = ngx_http_memc_cmd_set;
            is_storage_cmd = 1;

        } else if (r->method == NGX_HTTP_DELETE) {
            cmd_vv->len = sizeof("delete") - 1;
            cmd_vv->data = (u_char*) "delete";
            memc_cmd = ngx_http_memc_cmd_delete;

        } else {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
             "ngx_memc: $memc_cmd variable requires explicit "
             "assignment for HTTP request method %V",
             &r->method_name);

            return NGX_HTTP_BAD_REQUEST;
        }
    } else {
        memc_cmd = ngx_http_memc_parse_cmd(cmd_vv->data, cmd_vv->len, &is_storage_cmd);

        if (memc_cmd == ngx_http_memc_cmd_unknown) {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                     "ngx_memc: unknown $memc_cmd \"%v\"", cmd_vv);

            return NGX_HTTP_BAD_REQUEST;
        }
    }

    mlcf = ngx_http_get_module_loc_conf(r, ngx_http_memc_module);

    if ( ! ngx_http_memc_in_cmds_allowed(mlcf, memc_cmd) ) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                 "ngx_memc: User requests to run memcached command "
                 "\"%v\"", cmd_vv);

        return NGX_HTTP_FORBIDDEN;
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

    u->conf = &mlcf->upstream;

    ctx = ngx_palloc(r->pool, sizeof(ngx_http_memc_ctx_t));
    if (ctx == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ctx->memc_key_vv = key_vv;
    ctx->memc_value_vv = NULL;
    ctx->memc_flags_vv = NULL;

    ctx->parser_state = NGX_ERROR;

    ctx->rest = NGX_HTTP_MEMC_END;
    ctx->request = r;

    ctx->cmd_str.data = cmd_vv->data;
    ctx->cmd_str.len  = cmd_vv->len;

    ctx->cmd = memc_cmd;

    ctx->is_storage_cmd = is_storage_cmd;

    ngx_http_set_ctx(r, ctx, ngx_http_memc_module);

    if (is_storage_cmd) {
        u->create_request = ngx_http_memc_create_storage_cmd_request;
        u->process_header = ngx_http_memc_process_simple_header;

        u->input_filter_init = ngx_http_memc_empty_filter_init;
        u->input_filter = ngx_http_memc_empty_filter;

    } else if (memc_cmd == ngx_http_memc_cmd_get) {
        u->create_request = ngx_http_memc_create_get_cmd_request;
        u->process_header = ngx_http_memc_process_get_cmd_header;

        u->input_filter_init = ngx_http_memc_get_cmd_filter_init;
        u->input_filter = ngx_http_memc_get_cmd_filter;

    } else if (memc_cmd == ngx_http_memc_cmd_flush_all
            || memc_cmd == ngx_http_memc_cmd_version) {
        u->create_request = ngx_http_memc_create_noarg_cmd_request;
        u->process_header = ngx_http_memc_process_simple_header;

        u->input_filter_init = ngx_http_memc_empty_filter_init;
        u->input_filter = ngx_http_memc_empty_filter;

    } else {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
            "assertion failed: command \"%v\" does not have proper "
            "handlers.", cmd_vv);

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    u->reinit_request = ngx_http_memc_reinit_request;
    u->abort_request = ngx_http_memc_abort_request;
    u->finalize_request = ngx_http_memc_finalize_request;

    u->input_filter_ctx = ctx;

    if (is_storage_cmd || memc_cmd == ngx_http_memc_cmd_get) {
        hash_key = ngx_hash_key(ngx_http_memc_flags.data, ngx_http_memc_flags.len);

        flags_vv = ngx_http_get_variable(r, &ngx_http_memc_flags, hash_key, 1);

        if (flags_vv == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ctx->memc_flags_vv = flags_vv;
    }

    if (is_storage_cmd || memc_cmd == ngx_http_memc_cmd_incr
                || memc_cmd == ngx_http_memc_cmd_decr
                || memc_cmd == ngx_http_memc_cmd_verbosity)
    {
        hash_key = ngx_hash_key(ngx_http_memc_value.data, ngx_http_memc_value.len);

        value_vv = ngx_http_get_variable(r, &ngx_http_memc_value, hash_key, 1);
        if (value_vv == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ctx->memc_value_vv = value_vv;

        if (value_vv->not_found) {
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

#if defined(nginx_version) && nginx_version >= 8011

            r->main->count++;

#endif

            return NGX_DONE;
        }
    }

    rc = ngx_http_discard_request_body(r);

    if (rc != NGX_OK) {
        return rc;
    }

    ngx_http_upstream_init(r);

#if defined(nginx_version) && nginx_version >= 8011

            r->main->count++;

#endif

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


static ngx_flag_t
ngx_http_memc_in_cmds_allowed(ngx_http_memc_loc_conf_t *mlcf,
        ngx_http_memc_cmd_t memc_cmd)
{
    ngx_uint_t                   i;
    ngx_http_memc_cmd_t         *value;

    if (mlcf->cmds_allowed == NULL || mlcf->cmds_allowed->nelts == 0) {
        /* by default, all the memcached commands supported are allowed. */
        return 1;
    }

    value = mlcf->cmds_allowed->elts;

    for (i = 0; i < mlcf->cmds_allowed->nelts; i++) {
        if (memc_cmd == value[i]) {
            return 1;
        }
    }

    return 0;
}

