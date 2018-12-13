# $G/lexer.a: $(LEXER_SRCS) $(LEXER_ROOT) $(HOST_DMD_PATH) $(SRC_MAKE) $(STRING_IMPORT_FILES)
#	CC="$(HOST_CXX)" $(HOST_DMD_RUN) -lib -of$@ $(MODEL_FLAG) -J$G -L-lstdc++ $(DFLAGS) $(LEXER_SRCS) $(LEXER_ROOT)

# todo: get the model from the path
dmd -lib -of$3
