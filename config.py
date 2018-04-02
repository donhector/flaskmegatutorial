'''
Configuration module for the Flask app
'''

import os

class Config(object):

    SECRET_KEY = os.environ.get('SECRET_KEY') or 'Supersecret!'
