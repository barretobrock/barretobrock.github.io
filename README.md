# Personal Blog
This repo serves as a means of regenerating a static blog for personal projects. It uses [hugo](https://github.com/agriyakhetarpal/hugo-python-distributions) for static site generation

## Installation
This project will use Python 3.12.

1. Set up venv `pyenv shell 3.12 && python3.12 -m venv ~/venvs/bobrockblog-312`
2. Activate venv `source ~/venvs/bobrockblog-312/bin/activate`
3. Install pelican `python3 -m pip install hugo`
4. On project root, run `hugo new site blogrock`
5. Install theme `git submodule add https://github.com/vaga/hugo-theme-m10c.git themes/hugo-theme-m10c`
6. In `hugo.toml` on project root, ensure the new theme is set.

## Usage
### New Posts
1. Create a new post file, automatically dated and marked as draft:
    `hugo new content content/posts/post-title.md`
2. Hotload the site while editing the new post
    `hugo server -D`
3. When ready, publish the site
    `hugo`