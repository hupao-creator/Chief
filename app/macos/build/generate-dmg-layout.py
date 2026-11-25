"""Regenerate the Finder metadata for the alpha install image."""

from datetime import datetime, timezone
from pathlib import Path
from math import sin, pi

from PIL import Image, ImageDraw, ImageFont

from ds_store import DSStore
from mac_alias import Alias, TargetInfo, VolumeInfo

# Finder's background alias is relative to the volume root. Leave creation
# dates and catalog IDs unspecified so the layout travels between builds.
volume = "Install Chief Alpha"
epoch = datetime(1904, 1, 1, tzinfo=timezone.utc)
alias = Alias(
    volume=VolumeInfo(volume, epoch, b"H+", 0, 0, b"\0\0", posix_path=f"/Volumes/{volume}"),
    target=TargetInfo(
        0, ".install.png", 2, 0, epoch, b"\0" * 4, b"\0" * 4,
        levels_from=0, levels_to=0, folder_name=volume,
        carbon_path=f"{volume}:.install.png".encode(), posix_path="/.install.png",
    ),
)

with DSStore.open(str(Path(__file__).with_name("alpha-layout.dsstore")), "w+") as store:
    root = store["."]
    root["vSrn"] = ("long", 1)
    root["icvl"] = ("type", b"icnv")
    root["bwsp"] = {
        "WindowBounds": "{{160, 120}, {600, 344}}",
        "ShowSidebar": False, "ShowToolbar": False, "ShowTabView": False,
        "ShowPathbar": False, "ShowStatusBar": False,
    }
    root["icvp"] = {
        "viewOptionsVersion": 1, "arrangeBy": "none", "iconSize": 84.0,
        "textSize": 13.0, "labelOnBottom": True, "showItemInfo": False,
        "showIconPreview": False, "gridSpacing": 100.0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "backgroundType": 2, "backgroundImageAlias": alias.to_bytes(),
    }
    store["Chief Alpha.app"]["Iloc"] = (134, 209)
    store["Applications"]["Iloc"] = (466, 209)

# Draw at Retina resolution. Finder uses the DPI to lay out the image in points.
assets = Path(__file__).resolve().parent
resources = assets.parent / "Sources/Shared/PluginUI/Resources"
paper = Image.new("RGB", (1200, 624), "#fbf7ee")
draw = ImageDraw.Draw(paper)
ink = "#302d29"
ochre = "#a4492f"
title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 76)
body = ImageFont.truetype(str(resources / "fonts/inter-latin-wght-normal.ttf"), 28)
chinese = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 25)
draw.text((72, 42), "Install Chief Alpha", fill=ink, font=title, anchor="lt")
draw.text((75, 152), "Drag the app into Applications.", fill=ink, font=body, anchor="lt")
draw.text((75, 194), "将左侧应用拖入右侧文件夹。", fill="#686151", font=chinese, anchor="lt")

skillet = Image.open(resources / "ChiefOverviewIdle.png").convert("RGBA")
skillet.thumbnail((288, 150), Image.Resampling.LANCZOS)
paper.paste(skillet, (846, 75), skillet)
# A perforated edge and dot grid give the install surface a printed-paper feel.
draw.rectangle((0, 266, 1200, 624), fill="#f3eee3")
for x in range(0, 1200, 16):
    draw.line((x, 266, x + 8, 266), fill="#c4b9a8", width=2)
for y in range(286, 624, 28):
    for x in range(12, 1200, 28):
        draw.ellipse((x, y, x + 1, y + 1), fill="#d4caba")

# The shallow arc echoes the motion of the skillet on the app icon.
points = [(476 + i, round(422 - 36 * sin(pi * i / 248))) for i in range(249)]
draw.line(points, fill=ochre, width=5)
draw.line([(711, 399), points[-1], (699, 423)], fill=ochre, width=5)
paper.save(assets / "alpha-install.png", dpi=(144, 144))
