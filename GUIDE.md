## Pelican update guide
This guide serves to help me make regular updates to this site, as it's my first time maintaining a blog with `pelican`.

### Update Steps
First, note that the `content` branch is where the manipulation is done. The `main` branch is reserved for the final generated output. I'll put these instructions in script form for my benefit...
```bash
# First we generate the web content - make sure you're in the project root!
pelican content -o output -s publishconf.py -t ~/extras/pelican-themes/octopress --verbose
# Add web content files generated in the output folder to the main branch
ghp-import -m "Generate Pelican site" --no-jekyll -b main output -c www.bobrock.dev
# Then push the changes in the main branch
git push origin main
# Now add the content changes to the content branch
git add content/ && git commit -m "${MSG}" && git push origin content
```

### Extras
#### Themes
Still wrapping my head around changing a theme, but it seems like the most preferred means is through [pelican-themes](https://github.com/getpelican/pelican-themes). The steps from that repo's README are duplicated below:
```bash
# Clone the repo
git clone --recursive https://github.com/getpelican/pelican-themes ~/extras/pelican-themes
```
Then we edit the settings file (`pelicanconf.py`?) to have `THEME = "/home/user/pelican-themes/theme-name"`