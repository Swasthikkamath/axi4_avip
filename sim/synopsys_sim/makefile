# -s means silent mode
# The command executed along with the output will be displayed on the terminal
# To get only the ouput use 'silent' mode
#
# make target -s


# -n or --just-print
# Reads the makefile and prints every command it would execute to update the
# target, but without executing them.
#
# make target -n


# -i or --ignore-errors: errors are ignored in all recipes of all rules.
# The special target .IGNORE has the same effect if it has no prerequisites.
#
# make target -i


.IGNORE:
	compile
	simulate

# Use the target where we WANT silent mode
.SILENT:
	compile
	simulate
	usage

# First target runs when the user doesn't specify one -> usage
usage:
	echo "";
	echo "-----------------------------------------------------------------";
	echo "------------------------- Usage ---------------------------------";
	echo "";
	echo "make target <options> <variable>=<value>";
	echo "";
	echo "To compile use:";
	echo "make compile";
	echo "";
	echo "To provide compilation argument:";
	echo "make compile comp_args=\"+define+<macro_name>=<width> +define+<macro_name>=<width> +define+<macro_name>=<value>\"";
	echo "";
	echo "Example:";
	echo "make compile comp_args=\"+define+ADDRESS_WIDTH=64 +define+DATA_WIDTH=64 +define+DEFAULT_READY=1\"";
	echo "";
	echo "To simulate individual test:";
	echo "make simulate test=<test_name> uvm_verbosity=<VERBOSITY_LEVEL>";
	echo "";
	echo "Example:";
	echo "make simulate test=base_test uvm_verbosity=UVM_HIGH";
	echo "";
	echo "To provide seed number (default is random):";
	echo "make simulate test=<test_name> uvm_verbosity=<VERBOSITY_LEVEL> seed=<value>";
	echo "";
	echo "To run regression:";
	echo "make regression testlist_name=<regression_testlist_name.list>";
	echo "";
	echo "Example:";
	echo "make regression testlist_name=axi4LiteRegression.list";
	echo "";
	echo "To provide compilation argument in the regression:";
	echo "make regression comp_args=\"+define+<macro_name>=<width> +define+<macro_name>=<width> +define+<macro_name>=<value>\" testlist_name=axi4LiteRegression.list";
	echo "";
	echo "Example:";
	echo "make regression comp_args=\"+define+ADDRESS_WIDTH=64 +define+DATA_WIDTH=64 +define+DEFAULT_READY=1\" testlist_name=axi4LiteRegression.list";
	echo "";
	echo "-----------------------------------------------------------------";
	echo "-----------------------------------------------------------------";
	echo "";

all:
	make clean; make compile; make simulate;

# For Assertions use +acc options
#  +cover=becstf

VCS_CMD_RAND = vcs -full64 -sverilog -assert svaext +v2k -cm assert -debug_access+all -debug_acc+pp+dmptf -ntb_opts uvm-1.2 +ntb_random_seed_automatic +memcbk +vcs+fsdbon+all -override_timescale=1ns/1ps

select_mode:
	case "$(MODE)" in \
	  slave|master|b2b) ;; \
	  *) echo "ERROR: invalid MODE '$(MODE)'. Use MODE=slave|master|b2b"; exit 1 ;; \
	esac
	echo "Selecting compile MODE = $(MODE) (editing ../axi4_compile.f + hvl_top.sv in place)";
	sed -i -E '/@MODE=/ { /^\/\// ! s|^|//| }' ../axi4_compile.f
	sed -i -E '/@MODE=$(MODE)/ s|^//||' ../axi4_compile.f
	case "$(MODE)" in \
	  slave)  pkg=axi4_standalone_slave_test_pkg ;; \
	  master) pkg=axi4_standalone_master_test_pkg ;; \
	  b2b)    pkg=axi4_back_to_back_test_pkg ;; \
	esac; \
	sed -i -E "s|import axi4_[a-z0-9_]*_test_pkg::\*;|import $$pkg::*;|" ../../src/hvl_top/hvl_top.sv

compile:
	make select_mode MODE=$(MODE);
	${VCS_CMD_RAND} \
	$(comp_args) \
  +define+AXI_MODE_$(MODE) \
	-l Axi4LiteCompile.log \
	+plusarg_ignore \
	-f ../axi4_compile.f

	# -s means silent mode
	#  The command executed along with the output will be displayed on the terminal
	#  To get only the output use 'silent' mode
	# make compile_war_err -s
	# or use .SILENT
	make compile_war_err

# Setting a default test as base_test
ifndef test
override test = axi4_base_test
endif

# Setting the default uvm_verbosity to UVM_MEDIUM
ifndef uvm_verbosity
override uvm_verbosity = UVM_MEDIUM
endif

# Setting the default seed value to random
ifndef seed
override seed = random
endif

# Setting the default test folder to test name
ifndef test_folder
override test_folder = $(test)
endif

simulate:
	mkdir -p $(test_folder)

	# Use -novopt for no optimization - Makes the simulation slower
	./simv \
	-cm assert \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(uvm_verbosity) \
	-sv_seed $(seed) \
	-cm_dir $(test_folder)/coverage \
	-l $(test_folder)/$(test).log
	urg -report $(test_folder) -dir $(test_folder)/coverage.vdb

	# For checking and reporting simulation errors
	make simulate_war_err

clean:
	rm -rf csrc simv* work *.bak *.vpd transcript waves.shm *.wlf mylib lib *.vstf .restart* urgReport *.so vc_hdrs.h *.log *.fsdb *.key nWaveLog vfastLog *.conf *.vcd

##
## For Regression and coverage merge
##
regression:
	# Run compilation
	make compile MODE=$(MODE) comp_args="$(comp_args)"
	# Run simulation - regression
	python regression_handling.py $(testlist_name)
	# Merge coverage
	make merge_cov_report

merge_cov_report:
	# Merging all the coverage
	urg -report regressionReport -dir coverage.vdb -dir */*.vdb

	echo "";
	echo "-----------------------------------------------------------------";
	echo "Coverage report: firefox regressionReport/grp0.html &"
	echo "-----------------------------------------------------------------";
	echo "";


compile_war_err:
	echo "";
	echo "-----------------------------------------------------------------";
	echo "------------------- Compilation Report --------------------------";
	echo "";
	grep "^\*\* " Axi4LiteCompile.log;
	echo "";
	grep "^Error" Axi4LiteCompile.log;
	echo "";
	echo "Log file path: Axi4LiteCompile.log"
	echo "";
	echo "-----------------------------------------------------------------";
	echo "-----------------------------------------------------------------";
	echo "";

simulate_war_err:
	echo "";
	echo "-----------------------------------------------------------------";
	echo "-------------------- Simulation Report --------------------------";
	echo "";
	echo "Simulator Errors";
	grep "Error" $(test_folder)/$(test).log;
	echo "";
	echo "UVM Fatal";
	grep "UVM_FATAL" $(test_folder)/$(test).log;
	echo "";
	echo "UVM Errors";
	grep "UVM_ERROR" $(test_folder)/$(test).log;
	echo "";
	echo "UVM Warnings";
	grep "UVM_WARNING" $(test_folder)/$(test).log;
	echo "";
	echo "Testname: $(test)"
	echo "";
	echo "Log file path: $(test_folder)/$(test).log"
	echo "";
	echo "Waveform: verdi -ssf novas.fsdb"
	echo "";
	echo "Coverage: firefox $(test_folder)/grp0.html &"
	echo "-----------------------------------------------------------------";
	echo "-----------------------------------------------------------------";
	echo "";
