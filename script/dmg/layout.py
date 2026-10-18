"""Write Finder layout directly; packaging does not require GUI automation."""
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias
volume = Path(sys.argv[1])
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowToolbar': False, 'ShowSidebar': False,
        'ShowPathbar': False, 'ShowTabView': False,
        'ContainerShowSidebar': False, 'PreviewPaneVisibility': False,
        'SidebarWidth': 0,
        # Leave room for global Finder path/status bars even when it ignores
        # this volume's visibility preferences.
        'WindowBounds': '{{180, 160}, {680, 500}}',
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundColorRed': 0.96, 'backgroundColorGreen': 0.96, 'backgroundColorBlue': 0.96,
        'backgroundImageAlias': Alias.for_file(str(volume / '.background/background.png')).to_bytes(),
        'iconSize': 96.0, 'textSize': 14.0, 'gridSpacing': 100.0,
        'arrangeBy': 'none', 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['.']['icvl'] = ('type', b'icnv')
    store['ARose.app']['Iloc'] = (180, 205)
    store['Applications']['Iloc'] = (500, 205)
