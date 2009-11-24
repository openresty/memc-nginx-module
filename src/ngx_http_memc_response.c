#define DDEBUG 0
#include "ddebug.h"

#include "ngx_http_memc_response.h"
#include "ngx_http_memc_module.h"

u_char  ngx_http_memc_end[] = CRLF "END" CRLF;

ngx_int_t
ngx_http_memc_process_header(ngx_http_request_t *r)
{
    u_char                    *p, *len;
    ngx_str_t                  line;
    ngx_http_upstream_t       *u;
    ngx_http_memc_ctx_t  *ctx;

    u = r->upstream;

    dd("u->length: %d", u->length);

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
ngx_http_memc_filter_init(void *data)
{
    ngx_http_memc_ctx_t  *ctx = data;

    ngx_http_upstream_t  *u;

    u = ctx->request->upstream;

    u->length += NGX_HTTP_MEMCACHED_END;

    return NGX_OK;
}


ngx_int_t
ngx_http_memc_filter(void *data, ssize_t bytes)
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
                   ngx_http_memc_end + NGX_HTTP_MEMCACHED_END - ctx->rest,
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

    if (bytes <= (ssize_t) (u->length - NGX_HTTP_MEMCACHED_END)) {
        u->length -= bytes;
        return NGX_OK;
    }

    last += u->length - NGX_HTTP_MEMCACHED_END;

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

