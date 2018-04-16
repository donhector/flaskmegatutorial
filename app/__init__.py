"""Flask main application setup"""

from flask import Flask
from config import Config

# Initialize a Flask application
APP = Flask(__name__)
APP.config.from_object(Config)

# from our 'app' package, import the routes.py module
from app import routes
