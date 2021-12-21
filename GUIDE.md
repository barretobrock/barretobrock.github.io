## Pelican update guide
This guide serves to help me make regular updates to this site, as it's my first time maintaining a blog with `pelican`.

### Update Steps
First, note that the `content` branch is where the manipulation is done. The `main` branch is reserved for the final generated output. I'll put these instructions in script form for my benefit...
```bash
# First we generate the web content - make sure you're in the project root!
pelican content -o output -s publishconf.py
# Add web content files generated in the output folder to the main branch
ghp-import -m "Generate Pelican site" --no-jekyll -b main output -c www.bobrock.dev
# Then push the changes in the main branch
git push origin main
# Now add the content changes to the content branch
reap -p "Add your commit message: " MSG
git add content/ && git commit -m "${MSG}" && git push origin content
```