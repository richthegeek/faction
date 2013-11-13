test:
	@./node_modules/.bin/mocha -u tdd ./lib/processor/jobs/hook_send/test/

.PHONY: test
