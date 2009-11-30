# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => $Test::Nginx::LWP::RepeatEach * 2 * blocks();

#no_diff;

run_tests();

__DATA__

=== TEST 1: the "version" command
--- config
    location /ver {
        set $memc_cmd version;
        memc_pass 127.0.0.1:11984;
    }
--- request
    GET /ver
--- response_body_like: ^VERSION \d+(\.\d+)+\S*?\r\n$

