# 0.2.0

* Update the bundled Dynamsoft Capture Vision SDKs: desktop bundle 3.6.5000 on Windows, macOS, and Linux; `dynamsoft-capture-vision-bundle` 3.6.3200 on the web; `DynamsoftMRZScannerBundle` 3.6.2000 on Android and iOS.
* Fix the example preview cropping still images: built-in samples and picked files are letterboxed instead of cover-cropped, so passport MRZ and document samples stay fully visible.
* Show the parsed MRZ fields (document type plus every field) in the example result panel, and let the panel size to its content.

# 0.1.0

* Initial release: unified Capture Vision API with barcode, MRZ, and document boundary detection; file and raw-buffer capture; DCV settings JSON import with dynamic template-name discovery, exact named-template capture, and factory-default restore via `resetSettings()`.
