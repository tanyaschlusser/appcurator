README
######

Goals
=====

  0. Learn some Python
  1. Create a database containing apps and reviews of apps

      a. Design the structure of the database
      b. Implement

  2. Create a webpage that interacts with and shows the contents
     of the database, using Django

  3. Populate the database with apps found by searching the internet
     for health-related apps


Getting started
===============

You need to install Flask, pg8000, and other libraries
in the 'requirements.txt' file:

    pip install -r requirements.txt


If you don't want to do this in your own environment,
you can do it in a virtual environment:

    virtualenv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ## to deactivate the virtual environment,
    ## just type 'deactivate' (without quotes)



Heroku notes
============

These instructions help to
[deploy in Git](https://devcenter.heroku.com/articles/git).

There is an issue with storing passwords in a configuration
file -- you can't just add files to your Heroku repo, you
are supposed to use environment variables.
To add an environment variable to Heroku:

    heroku config:set DATABASE=<database value>
    heroku config:set HOST=<host value (ec2-something.amazon.com)>
    heroku config:set PORT=5432
    heroku config:set USER=<user name>
    heroku config:set PASSWORD=<password>


And then restart:

    heroku restart

To look at the logs while the app is running:

    heroku logs --tail

Schedule
========

Phone calls / Skype every other [[Saturday at 10am?]]


--> Sorry we're so behind Valentina


Thursday 8 January
    ChiPy Talk -- just 3 slides or so, unless you want more



The database
============

We will use heroku's default Postgresql database (currently 9.3)


The webpage
===========

We will host on heroku (which launches an Amazon Web Services instance)
