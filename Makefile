
new-post:
	hugo new content content/posts/$(filter-out $@, $(MAKECMDGOALS))/index.md

%:
	@: