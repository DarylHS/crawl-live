"""First-person launcher.  Usage: python fp_demo.py [--seed N]

The first-person view now lives in the real game (python main.py, Tab to switch).
This starts it in first-person; Tab still saves your choice.
"""
import argparse

from crawler.game import App

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Crawl Live! in first-person")
    ap.add_argument("--seed", type=int, help="fixed seed for a reproducible first run")
    app = App(seed=ap.parse_args().seed)
    app.view = "fp"
    app.run()
