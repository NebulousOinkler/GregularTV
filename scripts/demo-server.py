#!/usr/bin/env python3
"""A pretend Jellyfin server for App Store screenshots.

    swift scripts/make-demo-video.swift          # once: writes .build/demo/background.mp4
    python3 scripts/demo-server.py               # serves http://localhost:8765

Then launch a Debug build of the app with `-demoServer http://localhost:8765`
(see App/GregularTV/DemoMode.swift), in a simulator on this Mac.

The library is public-domain films and made-up TV shows, so screenshots show
nothing anyone else owns and nothing from a real library. Every item plays the
same plain background video. Only the endpoints the app calls are answered.
"""

import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = 8765
VIDEO = os.path.join(os.path.dirname(__file__), "..", ".build", "demo", "background.mp4")
TICKS_PER_MINUTE = 60 * 10_000_000

# Public-domain films (US): title, year, minutes, genres.
FILMS = [
    ("Nosferatu", 1922, 94, ["Horror"]),
    ("The Phantom of the Opera", 1925, 93, ["Horror"]),
    ("The Cabinet of Dr. Caligari", 1920, 76, ["Horror", "Thriller"]),
    ("Metropolis", 1927, 148, ["Science Fiction", "Drama"]),
    ("A Trip to the Moon", 1902, 13, ["Science Fiction", "Adventure"]),
    ("The Lost World", 1925, 93, ["Adventure", "Science Fiction"]),
    ("The General", 1926, 78, ["Comedy", "Action"]),
    ("Sherlock Jr.", 1924, 45, ["Comedy"]),
    ("Safety Last!", 1923, 74, ["Comedy"]),
    ("Our Hospitality", 1923, 65, ["Comedy"]),
    ("Steamboat Bill, Jr.", 1928, 70, ["Comedy"]),
    ("The Gold Rush", 1925, 95, ["Comedy", "Adventure"]),
    ("The Kid", 1921, 68, ["Comedy", "Family"]),
    ("The Thief of Bagdad", 1924, 149, ["Adventure", "Fantasy"]),
    ("The Mark of Zorro", 1920, 90, ["Action", "Adventure"]),
    ("The Great Train Robbery", 1903, 12, ["Action"]),
    ("Nanook of the North", 1922, 79, ["Documentary"]),
    ("Man with a Movie Camera", 1929, 68, ["Documentary"]),
    ("His Girl Friday", 1940, 92, ["Comedy"]),
    ("Charade", 1963, 113, ["Thriller", "Comedy"]),
    ("Detour", 1945, 68, ["Thriller"]),
    ("D.O.A.", 1949, 83, ["Thriller"]),
    ("Night of the Living Dead", 1968, 96, ["Horror"]),
    ("The Little Shop of Horrors", 1960, 72, ["Comedy", "Horror"]),
    ("Plan 9 from Outer Space", 1957, 79, ["Science Fiction", "Horror"]),
    ("Gulliver's Travels", 1939, 76, ["Animation", "Family"]),
]

# Made-up TV shows: name, year, minutes per episode, episodes, genres.
SHOWS = [
    ("Maple Street", 2019, 22, 20, ["Comedy"]),
    ("Two Doors Down", 2021, 22, 16, ["Comedy", "Sitcom"]),
    ("The Night Desk", 2018, 44, 18, ["Drama"]),
    ("Harbor Lights", 2020, 46, 16, ["Drama"]),
    ("Station Nine", 2022, 43, 14, ["Science Fiction", "Drama"]),
    ("Far Signal", 2017, 45, 12, ["Sci-Fi & Fantasy"]),
    ("Orbit & Pip", 2016, 11, 30, ["Animation", "Kids"]),
    ("Paper Lanterns", 2015, 22, 20, ["Animation", "Family"]),
    ("Wild Coasts", 2021, 50, 10, ["Documentary"]),
    ("Small Wonders", 2019, 25, 14, ["Documentary", "Family"]),
    ("The Great Garden Swap", 2022, 44, 12, ["Reality"]),
    ("Kitchen Heat", 2023, 42, 14, ["Reality"]),
]

EPISODE_TITLES = [
    "Pilot", "New Neighbours", "The Long Weekend", "Lights Out", "Home Again", "The Big Storm",
    "Second Chances", "Open House", "The Wrong Train", "Late Shift", "Midsummer", "The Letter",
    "Snow Day", "Crossroads", "Full Circle", "The Visitor", "High Tide", "Old Friends",
    "Moving Day", "The Last Word", "Night Market", "Paper Trail", "Blue Hour", "Homecoming",
    "Fair Weather", "The Map", "Quiet Street", "First Light", "Long Way Round", "Finale",
]

COMMERCIALS = [
    ("Sunny Orchard Juice", 30), ("Blue Line Trains", 30), ("Cozy Knit Sweaters", 15),
    ("Harbor Bakery", 30), ("Brightside Toothpaste", 20), ("Maple Street Hardware", 30),
    ("Starfield Planetarium", 45), ("Fresh Fold Laundry", 15), ("Parkside Pet Supplies", 30),
    ("Golden Crust Pizza", 30), ("Evergreen Garden Centre", 20), ("Night Owl Coffee", 30),
]


def item(id, name, type, minutes, **extra):
    return {"Id": id, "Name": name, "Type": type, "RunTimeTicks": int(minutes * TICKS_PER_MINUTE), **extra}


def build_library():
    series, playable = [], []
    for i, (title, year, minutes, genres) in enumerate(FILMS):
        playable.append(item(f"film{i}", title, "Movie", minutes, ProductionYear=year, Genres=genres,
                             PremiereDate=f"{year}-01-01T00:00:00.0000000Z"))
    for s, (name, year, minutes, count, genres) in enumerate(SHOWS):
        series_id = f"show{s}"
        series.append({"Id": series_id, "Name": name, "Type": "Series", "ProductionYear": year, "Genres": genres})
        per_season = 10
        for e in range(count):
            season, number = e // per_season + 1, e % per_season + 1
            playable.append(item(f"{series_id}e{e}", EPISODE_TITLES[(e + s * 7) % len(EPISODE_TITLES)],
                                 "Episode", minutes, SeriesId=series_id, SeriesName=name,
                                 ParentIndexNumber=season, IndexNumber=number,
                                 PremiereDate=f"{year + season - 1}-{(number % 12) + 1:02d}-01T00:00:00.0000000Z"))
    commercials = [item(f"ad{i}", name, "Video", seconds / 60) for i, (name, seconds) in enumerate(COMMERCIALS)]
    return series, playable, commercials


SERIES, PLAYABLE, COMMERCIAL_ITEMS = build_library()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass  # quiet

    def send_json(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_empty(self, status=204):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def items_page(self, query):
        types = query.get("IncludeItemTypes", [""])[0].split(",")
        if query.get("ParentId", [""])[0] == "commercials":
            items = COMMERCIAL_ITEMS
        elif types == ["Series"]:
            items = SERIES
        else:
            items = [i for i in PLAYABLE if i["Type"] in types]
        start = int(query.get("StartIndex", ["0"])[0])
        limit = int(query.get("Limit", ["500"])[0])
        return {"Items": items[start:start + limit], "TotalRecordCount": len(items)}

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if url.path == "/UserViews":
            return self.send_json({"Items": [{"Id": "commercials", "Name": "Commercials", "Type": "CollectionFolder"}],
                                   "TotalRecordCount": 1})
        if url.path == "/Items":
            return self.send_json(self.items_page(query))
        if url.path == "/Playback/BitrateTest":
            size = int(query.get("size", ["64000"])[0])
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.end_headers()
            self.wfile.write(b"\0" * size)
            return
        if re.fullmatch(r"/Videos/[^/]+/stream(\.\w+)?", url.path):
            return self.send_video()
        self.send_empty(404)

    def do_HEAD(self):
        if re.fullmatch(r"/Videos/[^/]+/stream(\.\w+)?", urlparse(self.path).path):
            return self.send_video(head=True)
        self.send_empty(404)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0") or 0))
        path = urlparse(self.path).path
        if path.endswith("/PlaybackInfo"):
            return self.send_json({"MediaSources": [{"Id": "source", "SupportsDirectPlay": True, "Container": "mp4"}],
                                   "PlaySessionId": "demo"})
        self.send_empty()  # capabilities, logout

    def do_DELETE(self):
        self.send_empty()  # stop transcoding: nothing to stop

    def send_video(self, head=False):
        size = os.path.getsize(VIDEO)
        start, end = 0, size - 1
        match = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if match:
            if match.group(1):
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else end
            else:  # suffix range: the last N bytes
                start = max(0, size - int(match.group(2)))
        end = min(end, size - 1)
        self.send_response(206 if match else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if match:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head:
            return
        with open(VIDEO, "rb") as file:
            file.seek(start)
            self.wfile.write(file.read(end - start + 1))


if __name__ == "__main__":
    if not os.path.exists(VIDEO):
        sys.exit(f"Missing {VIDEO}. Run: swift scripts/make-demo-video.swift")
    print(f"Demo Jellyfin server on http://localhost:{PORT} "
          f"({len(FILMS)} films, {len(SHOWS)} shows, {len(COMMERCIALS)} commercials). Ctrl-C to stop.")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
