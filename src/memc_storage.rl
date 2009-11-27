%%{
    machine memc_storage;

    include memc_common "memc_common.rl";

    action handle_stored {
        dd("status set to 201");

        *status_addr = NGX_HTTP_CREATED;
    }

    response = "STORED\r\n" @handle_stored
             | "NOT_STORED\r\n"
             | "EXISTS\r\n"
             | "NOT_FOUND\r\n"
             | error
             ;

    main := response @finalize
         ;

}%%

