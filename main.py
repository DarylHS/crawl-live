"""Launch Crawl Live!  Usage: python main.py [--seed N]"""
import argparse

from crawler.game import main

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Crawl Live! A game-show roguelike.")
    parser.add_argument("--seed", type=int, help="fixed seed for a reproducible first run")
    main(parser.parse_args().seed)
