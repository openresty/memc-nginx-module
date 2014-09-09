%%{
    machine memc_touch;

    alphtype short;

    include memc_common "memc_common.rl";

    response = "TOUCHED\r\n"
             | "NOT_FOUND\r\n" @handle_not_found
             | error
             ;

    main := response @finalize
         ;

}%%

