# Personal Blog
This repo serves as a means of regenerating a static blog for personal projects. It uses [aurora](https://github.com/capjamesg/aurora) for static site generation

## Installation
This project will use Python 3.12.

1. Set up venv `pyenv shell 3.12 && python3.12 -m venv ~/venvs/bobrockblog-312`
2. Activate venv `source ~/venvs/bobrockblog-312/bin/activate`
3. Install pelican `python3 -m pip install aurora-ssg`
4. On project root, run `pelican-quickstart`