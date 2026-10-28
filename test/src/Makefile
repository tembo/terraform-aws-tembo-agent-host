.DEFAULT_GOAL := test

## Run the Terratest suite, which applies examples/complete in AWS
test:
	go mod download
	go test -v -timeout 60m

## Remove state the tests leave behind
clean:
	rm -rf ../../examples/complete/*.tfstate* ../../examples/complete/.terraform ../../examples/complete/.terraform.lock.hcl

.PHONY: test clean
