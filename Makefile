
new-post:
	hugo new content content/posts/$(filter-out $@, $(MAKECMDGOALS))/index.md
run-local:
	hugo server -D
publish:
	hugo

%:
	@: