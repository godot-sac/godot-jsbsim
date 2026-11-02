"""Records the README animation: the terrain demo flying its autopilot route (Godot's Movie Maker, PNG frames), then
writes a 16 s clip of the turn over Esenboğa as an animated WebP (for the README) and a GIF (for places that only
take GIFs). Both are too large for git; they are attached to the GitHub release (docs/release.md).

Needs a window (not --headless), the terrain demo set up (python tools/link_siblings.py, godot-geo's ankara_60km
package) and Pillow (pip install pillow). Takes about 10 minutes, mostly PNG encoding.

Usage (from the repo root):
    python tools/make_media.py --godot <path to the Godot executable> [--out build/media] [--frames DIR]
    python tools/make_media.py --frames DIR          # only rebuild the clips from frames recorded before
"""
import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FPS = 25
TIME_SCALE = 2           # the clip plays at twice the real speed
SIM_SECONDS = 156
CLIP_START = 1520        # first frame of the clip (the turn after waypoint 1, airport on the right)
CLIP_FRAMES = 400        # 16 s of video
WIDTH = 640


def record(godot: str, frames: Path) -> None:
    frames.mkdir(parents=True, exist_ok=True)
    for old in frames.glob("f*.png"):
        old.unlink()
    command = [godot, "--path", str(ROOT), "--write-movie", str(frames / "f.png"), "--fixed-fps", str(FPS),
               "--resolution", "1280x720", "res://demo/terrain_flight.tscn", "--",
               "--route", "--no-hud", "--time-scale", str(TIME_SCALE), "--seconds", str(SIM_SECONDS)]
    print(" ".join(command))
    subprocess.run(command, check=True)


def load_clip(frames: Path, step: int) -> list[Image.Image]:
    clip = []
    for i in range(CLIP_START, CLIP_START + CLIP_FRAMES + 1, step):
        image = Image.open(frames / f"f{i:08d}.png").convert("RGB")
        clip.append(image.resize((WIDTH, round(image.height * WIDTH / image.width)), Image.LANCZOS))
    return clip


def write_gif(clip: list[Image.Image], step: int, target: Path) -> None:
    # One palette for all frames (no flicker), from every 8th frame; the centre, where the aircraft is, counts
    # several times more so its colour survives.
    samples = clip[::8]
    w, h = clip[0].size
    centres = [image.crop((w * 3 // 8, h * 3 // 8, w * 5 // 8, h * 5 // 8)) for image in samples]
    cw, ch = centres[0].size
    mosaic = Image.new("RGB", (w + 4 * cw, h * len(samples)))
    for k, image in enumerate(samples):
        mosaic.paste(image, (0, k * h))
        for r in range(4):
            for c in range(2):
                mosaic.paste(centres[k], (w + r * cw, k * h + c * ch))
    palette = mosaic.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    frames = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in clip]
    frames[0].save(target, save_all=True, append_images=frames[1:], duration=round(1000 * step / FPS), loop=0,
                   optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", help="record new frames with this Godot executable")
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "media")
    parser.add_argument("--frames", type=Path, help="frame folder (default <out>/frames)")
    args = parser.parse_args()
    frames = args.frames or args.out / "frames"
    if args.godot:
        record(args.godot, frames)
    if not (frames / f"f{CLIP_START + CLIP_FRAMES:08d}.png").is_file():
        print(f"no recorded frames in {frames}; pass --godot", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    clip = load_clip(frames, 2)  # 12.5 frames per second
    webp = args.out / "godot-jsbsim-flight.webp"
    clip[0].save(webp, save_all=True, append_images=clip[1:], duration=round(2000 / FPS), loop=0, quality=60,
                 method=6)
    gif = args.out / "godot-jsbsim-flight.gif"
    write_gif(clip, 2, gif)
    for path in (webp, gif):
        print(f"{path}: {path.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
