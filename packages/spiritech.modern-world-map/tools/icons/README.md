Sources for the toolbar icons in ../../assets/. Render at 2x (36px, shown at 18px):

    for i in me mission; do rsvg-convert -w 36 -h 36 $i.svg -o ../../assets/$i.png; done

Palette (modern-common/theme): teal #4FB3BF, gold #F0C060, player dot #FFD84A (as on the
map), outline #0D1015, light #C5CCD6.
