# Hintergründe – Quellen

Die sechs Vektor-Motive (Katze, Tropfen, Taschenlampe, Planeten, Insel, Glasbruch) sind HTML/SVG-Dateien und werden mit Headless Chrome in 5120 × 2880 gerendert:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=5120,2880 --virtual-time-budget=2000 --screenshot=katze.png file://$PWD/katze.html
```

Die acht Foto- und Illustrationsmotive (Programmierer, Weizenfeld, Astronaut, Katzen am Schreibtisch, Weltraum, Sonnenuntergang, Dschungel, Hängekatze) sind KI-generiert (Magnific, 16:9, 4K) und auf 5120 × 2880 beschnitten. Alle fertigen Bilder liegen als JPEG in `Resources/Hintergruende`.
