"""Build the bundled example from original art and declarative data only."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(__file__).resolve().parents[1]
sample = root / 'samples/ModernEraExpansion'
output = root / 'Launcher/src/main/assets/modern-era-sample.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for file in sorted(sample.rglob('*')):
        if file.is_file():
            archive.write(file, file.relative_to(sample))
print(output)
