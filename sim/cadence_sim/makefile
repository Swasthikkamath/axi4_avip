# -s means silent mode
# The command executed along with the output will be displayed on the terminal
# To get only the ouput use 'silent' mode
#
# make target -s


# -n or --just-print
# The first test I perform on a new makefile target is to invoke make with the --just-print (-n) option.
# This causes make to read the makefile and print every command it would normally execute to
# update the target but without executing them.
#
# make target -n


# When you run make with the -i or --ignore-errors flag,
# errors are ignored in all recipes of all rules.
# A rule in the makefile for the special target .IGNORE has the same effect,
# if there are no prerequisites. This is less flexible but sometimes useful.
# When errors are to be ignored, because of -i flag, make treats an error return just like success,
# except that it prints out a message that tells you the status code the shell exited with,
# and says that the error has been ignored.
#
# make target -i

.IGNORE:
	compile
	simulate

# WE can also use the target where we WANT the silent mode
.SILENT:
	compile
	simulate
	usage

# First target will be executed incase the user doesn't mention
# the target to execute
# In this case, usage will be executed
# Usage
usage:
	@echo "";
	@echo "-----------------------------------------------------------------";
	@echo "------------------------- Usage ---------------------------------";
	@echo "";
	@echo "make target <options> <variable>=<value>";
	@echo "";
	@echo "To compile use:"
	@echo "make compile";
	@echo "";
	@echo "To simulate use:"
	@echo "make simulate test=<test_name> uvm_verbosity=<VERBOSITY_LEVEL>";
	@echo "";
	@echo "Example:":
	@echo "make simulate test=axi4_base_test uvm_verbosity=UVM_HIGH";
	@echo "";
	@echo "To run regression:"
	@echo "make regression testlist_name=<regression_testlist_name.list>";
	@echo "";
	@echo "Example:":
	@echo "make regression testlist_name=axi4_transfers_regression.list";
	@echo "";
	@echo "-----------------------------------------------------------------";
	@echo "-----------------------------------------------------------------";
	@echo "";

all:
	make clean_compile; make compile; make simulate;

clean_compile: 
	rm -rf *_compile.log *_compile.history xcelium.d

clean_simulate: 
	rm -rf *Test cov_work

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
	make clean_compile;
	make select_mode MODE=$(MODE);
	xrun -c \
	-elaborate \
	-access +rwc \
	-64 \
	-sv \
	-uvm \
	+access+rw \
	+define+AXI_MODE_$(MODE) \
	-f ../axi4_compile.f \
  -access +r +vcd \
	-l axi4_compile.log \
	-coverage all \
	-sva 

	make compile_war_err

	# -s means silent mode
	#  The command executed along with the output will be displayed on the terminal
	#  To get only the ouput use 'silent' mode
	# make compile_war_err -s
	# or use .SILENT

# Setting a default test as base_test
ifndef test
override test := axi4_base_test
endif

ifndef test_folder
override test_folder := $(test)
endif

ifndef uvm_verbosity
override uvm_verbosity := UVM_MEDIUM
endif

# Setting the default seed value to random
ifndef seed
override seed = random
endif


simulate:
	mkdir -p $(test_folder)
	xrun -R \
	-64 \
	-sv \
	-uvm \
  +sv_seed=$(seed) \
	+UVM_TESTNAME=$(test) \
	+UVM_VERBOSITY=$(uvm_verbosity) \
	-l $(test_folder)/$(test).log \
	-coverage all \
	-covoverwrite \
	-covtest $(test_folder)/ \
  +plusarg_ignore \

	mv *.vcd $(test_folder)/$(test).vcd
	# For checking and reporting simulation errors
	make simulate_war_err

regression:
	#Run compilation
	make compile MODE=$(MODE);
	#Run simualtion - regression
	python regression_handling.py $(testlist_name)
	#	# Get the tests from regression list
	#	Merge coverage
	make merge_cov_report

merge_cov_report:
	imc -execcmd "merge cov_work/scope/* -out merged -initial_model union_all -overwrite; exit"
	imc -load cov_work/scope/merged

clean_all:
	make clean_compile;
	make clean_simulate;

compile_war_err:
	echo "";
	echo "-----------------------------------------------------------------";
	echo "------------------- Compilation Report --------------------------";
	echo "";
	grep "**" axi4_compile.log;
	echo "";
	grep "*Error" axi4_compile.log;
	echo "";
	echo "Log file path: axi4_compile.log"
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
	echo "Waveform: simvision $(test_folder)/$(test).vcd &"
	echo "";
	echo "-----------------------------------------------------------------";
	echo "-----------------------------------------------------------------";
	echo "";
