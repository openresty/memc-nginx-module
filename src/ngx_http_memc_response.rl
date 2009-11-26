#define DDEBUG 1
#include "ddebug.h"

#include "ngx_http_memc_response.h"
#include "ngx_http_memc_module.h"

%% machine memc_storage;
%% write data;

%% machine memc_flush_all;
%% write data;

u_char  ngx_http_memc_end[] = CRLF "END" CRLF;

ngx_int_t
ngx_http_memc_process_storage_cmd_header(ngx_http_request_t *r)
{
    int                     cs;
    u_char                  *p;
    u_char                  *pe;
    u_char                  *eof = NULL;
    ngx_str_t               resp;
    ngx_http_upstream_t     *u;
    ngx_http_memc_ctx_t     *ctx;
    ngx_buf_t               *b;
    ngx_chain_t             *cl, **ll;
    ngx_uint_t              status = NGX_HTTP_OK;

    dd("process storage cmd header");

    ctx = ngx_http_get_module_ctx(r, ngx_http_memc_module);

    if (ctx->parser_state == NGX_ERROR) {
        %% write init;
    }

    u = r->upstream;

    b = &u->buffer;

    p  = b->pos;
    pe = b->last;

    %%{
        machine memc_storage;

        action catch_err {
            status = NGX_HTTP_BAD_GATEWAY;
        }

        msg = any* -- "\r\n";

        error = "ERROR\r\n"
              | "CLIENT_ERROR " msg "\r\n"
              | "SERVER_ERROR " msg "\r\n"
              ;

        main := "STORED\r\n"
              | "EXISTS\r\n"
              | "NOT_FOUND\r\n"
              | error %catch_err
              ;
    }%%

    %% write exec;

    ctx->parser_state = cs;

    resp.data = b->pos;
    resp.len  = p - resp.data;

    dd("memcached response: %s", resp.data);

    if (cs >= memc_storage_first_final) {
        dd("memcached response parsed (resp.len: %d)", resp.len);

        r->headers_out.content_length_n = resp.len;
        u->headers_in.status_n = status;
        u->state->status = status;

        for (cl = u->out_bufs, ll = &u->out_bufs; cl; cl = cl->next) {
            ll = &cl->next;
        }

        cl = ngx_chain_get_free_buf(ctx->request->pool, &u->free_bufs);
        if (cl == NULL) {
            return NGX_ERROR;
        }

        cl->buf->flush = 1;
        cl->buf->memory = 1;
        cl->buf->pos = b->pos;
        cl->buf->last = b->last;

        *ll = cl;

        return NGX_OK;
    }

    if (cs == memc_storage_error) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "memcached sent invalid response for storange commands: "
                      "%V", &resp);

        status = NGX_HTTP_BAD_GATEWAY;
        u->headers_in.status_n = status;
        u->state->status = status;

        return status;
    }

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_memc_empty_filter_init(void *data)
{
    ngx_http_memc_ctx_t  *ctx = data;
    ngx_http_upstream_t  *u;

    u = ctx->request->upstream;

    u->length = 0;

    return NGX_OK;
}

ngx_int_t
ngx_http_memc_empty_filter(void *data, ssize_t bytes)
{
    ngx_http_memc_ctx_t  *ctx = data;

    /* u_char               *last; */
    ngx_buf_t            *b;
    ngx_chain_t          *cl, **ll;
    ngx_http_upstream_t  *u;

    dd("empty memcached filter");

    u = ctx->request->upstream;
    b = &u->buffer;

    dd("buffer len %d", b->last - b->pos);

    if (b->last - b->pos == 0) {
        return NGX_OK;
    }

    for (cl = u->out_bufs, ll = &u->out_bufs; cl; cl = cl->next) {
        ll = &cl->next;
    }

    cl = ngx_chain_get_free_buf(ctx->request->pool, &u->free_bufs);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    cl->buf->flush = 1;
    cl->buf->memory = 1;
    cl->buf->pos = b->pos;
    cl->buf->last = b->last;

    *ll = cl;

    return NGX_OK;
}


ngx_int_t
ngx_http_memc_get_cmd_filter_init(void *data)
{
    ngx_http_memc_ctx_t  *ctx = data;

    ngx_http_upstream_t  *u;

    u = ctx->request->upstream;

    dd("filter init: u->length: %d", u->length);

    u->length += NGX_HTTP_MEMC_END;

    dd("filter init (2): u->length: %d", u->length);

    return NGX_OK;
}


ngx_int_t
ngx_http_memc_get_cmd_filter(void *data, ssize_t bytes)
{
    ngx_http_memc_ctx_t  *ctx = data;

    u_char               *last;
    ngx_buf_t            *b;
    ngx_chain_t          *cl, **ll;
    ngx_http_upstream_t  *u;

    u = ctx->request->upstream;
    b = &u->buffer;

    if (u->length == ctx->rest) {

        if (ngx_strncmp(b->last,
                   ngx_http_memc_end + NGX_HTTP_MEMC_END - ctx->rest,
                   ctx->rest)
            != 0)
        {
            ngx_log_error(NGX_LOG_ERR, ctx->request->connection->log, 0,
                          "memcached sent invalid trailer");
        }

        u->length = 0;
        ctx->rest = 0;

        return NGX_OK;
    }

    for (cl = u->out_bufs, ll = &u->out_bufs; cl; cl = cl->next) {
        ll = &cl->next;
    }

    cl = ngx_chain_get_free_buf(ctx->request->pool, &u->free_bufs);
    if (cl == NULL) {
        return NGX_ERROR;
    }

    cl->buf->flush = 1;
    cl->buf->memory = 1;

    *ll = cl;

    last = b->last;
    cl->buf->pos = last;
    b->last += bytes;
    cl->buf->last = b->last;
    cl->buf->tag = u->output.tag;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ctx->request->connection->log, 0,
                   "memcached filter bytes:%z size:%z length:%z rest:%z",
                   bytes, b->last - b->pos, u->length, ctx->rest);

    if (bytes <= (ssize_t) (u->length - NGX_HTTP_MEMC_END)) {
        u->length -= bytes;
        return NGX_OK;
    }

    last += u->length - NGX_HTTP_MEMC_END;

    if (ngx_strncmp(last, ngx_http_memc_end, b->last - last) != 0) {
        ngx_log_error(NGX_LOG_ERR, ctx->request->connection->log, 0,
                      "memcached sent invalid trailer");
    }

    ctx->rest -= b->last - last;
    b->last = last;
    cl->buf->last = last;
    u->length = ctx->rest;

    return NGX_OK;
}


ngx_int_t
ngx_http_memc_process_get_cmd_header(ngx_http_request_t *r)
{
    u_char                    *p, *len;
    ngx_str_t                  line;
    ngx_http_upstream_t       *u;
    ngx_http_memc_ctx_t       *ctx;

    u = r->upstream;

    dd("process header: u->length: %d", u->length);

    for (p = u->buffer.pos; p < u->buffer.last; p++) {
        if (*p == LF) {
            goto found;
        }
    }

    return NGX_AGAIN;

found:

    *p = '\0';

    line.len = p - u->buffer.pos - 1;
    line.data = u->buffer.pos;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "memcached: \"%V\"", &line);

    p = u->buffer.pos;

    ctx = ngx_http_get_module_ctx(r, ngx_http_memc_module);

    if (ngx_strncmp(p, "VALUE ", sizeof("VALUE ") - 1) == 0) {

        p += sizeof("VALUE ") - 1;

        if (ngx_strncmp(p, ctx->key.data, ctx->key.len) != 0) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "memcached sent invalid key in response \"%V\" "
                          "for key \"%V\"",
                          &line, &ctx->key);

            return NGX_HTTP_UPSTREAM_INVALID_HEADER;
        }

        p += ctx->key.len;

        if (*p++ != ' ') {
            goto no_valid;
        }

        /* skip flags */

        while (*p) {
            if (*p++ == ' ') {
                goto length;
            }
        }

        goto no_valid;

    length:

        len = p;

        while (*p && *p++ != CR) { /* void */ }

        r->headers_out.content_length_n = ngx_atoof(len, p - len - 1);
        if (r->headers_out.content_length_n == -1) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "memcached sent invalid length in response \"%V\" "
                          "for key \"%V\"",
                          &line, &ctx->key);
            return NGX_HTTP_UPSTREAM_INVALID_HEADER;
        }

        u->headers_in.status_n = 200;
        u->state->status = 200;
        u->buffer.pos = p + 1;

        return NGX_OK;
    }

    if (ngx_strcmp(p, "END\x0d") == 0) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "key: \"%V\" was not found by memcached", &ctx->key);

        u->headers_in.status_n = 404;
        u->state->status = 404;

        return NGX_OK;
    }

no_valid:

    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                  "memcached sent invalid response: \"%V\"", &line);

    return NGX_HTTP_UPSTREAM_INVALID_HEADER;
}

ngx_int_t
ngx_http_memc_process_flush_all_cmd_header(ngx_http_request_t *r)
{
    int                     cs;
    u_char                  *p;
    u_char                  *pe;
    u_char                  *eof = NULL;
    ngx_str_t               resp;
    ngx_http_upstream_t     *u;
    ngx_http_memc_ctx_t     *ctx;
    ngx_buf_t               *b;
    ngx_chain_t             *cl, **ll;
    ngx_uint_t              status = NGX_HTTP_OK;

    dd("process flush_all cmd header");

    ctx = ngx_http_get_module_ctx(r, ngx_http_memc_module);

    if (ctx->parser_state == NGX_ERROR) {
        %% write init;
    }

    u = r->upstream;

    b = &u->buffer;

    p  = b->pos;
    pe = b->last;

    %%{
        machine memc_flush_all;

        action catch_err {
            status = NGX_HTTP_BAD_GATEWAY;
        }

        msg = any* -- "\r\n";

        error = "ERROR\r\n"
              | "CLIENT_ERROR " msg "\r\n"
              | "SERVER_ERROR " msg "\r\n"
              ;

        main := "OK\r\n"
              | error %catch_err
              ;
    }%%

    %% write exec;

    ctx->parser_state = cs;

    resp.data = b->pos;
    resp.len  = p - resp.data;

    dd("memcached response: %s", resp.data);

    if (cs >= memc_flush_all_first_final) {
        dd("memcached response parsed (resp.len: %d)", resp.len);

        r->headers_out.content_length_n = resp.len;
        u->headers_in.status_n = status;
        u->state->status = status;

        for (cl = u->out_bufs, ll = &u->out_bufs; cl; cl = cl->next) {
            ll = &cl->next;
        }

        cl = ngx_chain_get_free_buf(ctx->request->pool, &u->free_bufs);
        if (cl == NULL) {
            return NGX_ERROR;
        }

        cl->buf->flush = 1;
        cl->buf->memory = 1;
        cl->buf->pos = b->pos;
        cl->buf->last = b->last;

        *ll = cl;

        return NGX_OK;
    }

    if (cs == memc_flush_all_error) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "memcached sent invalid response for the flush_all commands: "
                      "%V", &resp);

        status = NGX_HTTP_BAD_GATEWAY;
        u->headers_in.status_n = status;
        u->state->status = status;

        return status;
    }

    return NGX_AGAIN;
}

