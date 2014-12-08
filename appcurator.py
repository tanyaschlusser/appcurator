#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# hello.py
"""
First attempt at showing database contents online. Does not
truly incorporate logins. Does not incorporate REST.
Experimentation now -- including logins and database access.

The pages we want to make are:
    /apps/
    /apps/<id>
    /login
    /logout
    /profile
    /providers/
    /providers/<id>
    /recommendations/
    /recommendations/<id>
    /reviews/
    /reviews/<id>
"""
import os
import pg8000

from flask import abort, flash, Flask, g, render_template, request, session, url_for
from flask.views import MethodView
from jinja2 import Template

## Local configuration settings -- database connection, passwords
import configuration as conf

## Setup
app = Flask(__name__)
app.config["THIS_DIR"] = os.path.dirname(os.path.abspath(__file__))
app.config["AVATAR_DIR"] = app.config["THIS_DIR"] + "/static/avatars/"
app.config["ICON_DIR"] = app.config["THIS_DIR"] + "/static/icons/"

## ------------------------------------------------- Database parts ----- ##
def get_db():
    """Set the flask 'g' value for _database, and return it."""
    db = getattr(g, "_database", None)
    if db is None:
        db = g._database = conf.connect_db()
    return db


@app.teardown_appcontext
def close_connection(exception):
    """Set the flask 'g' value for _database, and return it."""
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()
    g._database = None


def db_query(query, args=None, commit=False):
    """Perform a query returning the database cursor if success else None.

    Use db_select for SELECT queries.
    Wrap the query with a try/except, catch the error, and return
    False if the query fails.
    """
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(query, args)
        if commit:
            db.commit()
    except pg8000.ProgrammingError as e:
        return None
    return cur
    

def db_select(query, args=None, columns=None):
    """Perform a select query, returning a generator over the rows.

    The generator yields a dictionary with the keys as in the
    taken from the 'columns' argument, or else 'v0' ... 'vN' for the
    N columns returned.

    If there is an error with the query, return None.

    Keyword arguments
    args -- passed to pg8000.cursor.execute() for a secure
            parameterized query.
    """
    cur = db_query(query, args=args) 
    if cur is None:
        raise StopIteration()
    results = cur.fetchall()
    if len(results) == 0:
        raise StopIteration()
    if len(results[0]) > len(columns):
        columns = list(columns) + ["col%d" % i for i in range(len(columns),len(results))]
    elif len(results[0]) < len(columns):
        columns = columns[0:len(results[0])]
    for result in results:
        yield dict(zip(columns, result))


## ---------------------------------------------------- Login parts ----- ##
# This section will handle communication with Facebook to
# confirm the identity of the individual logging in, once
# we use Facebook's OAuth service.
def confirm_user_identity(userid, token):
    return True

def is_logged_in():
    return True


## -------------------------------------------- False RESTful parts ----- ##
def get_apps(appid="", devices="", tags=""):
    pass

def get_rest(path, query={}):
    """To be replaced by a query to a RESTful API later."""
    apis = {
        "apps": get_apps}
    if path in apis:
        return apis[path](**query)
    else:
        return None

## ------------------------------------------------------ Web parts ----- ##
@app.route("/")
def index():
    """The main page is at /apps, so redirect."""
    return redirect(url_for('show_apps'))


@app.route("/about")
def about():
    """About is a static page."""
    return render_template('about.html', title="About us")


@app.route("/apps", methods=['GET', 'POST'])
def apps():
    """Show summary of apps by topic or individual apps depending on request.

    At the top level show tag category summaries.
    At the app level show reviews in descending date order.
    Otherwise show  individual app summaries within the topic.
    """
    error = None
    if 'tags' in request.form:
        response = {}
        response["title"] = "App"
    elif 'review' in request.form:
        logged_in = is_logged_in()
        if logged_in:
            return redirect(url_for('review_app'))
        else:
            return redirect(url_for('login'))
    else:
        # Show summaries of the topics, in descending order
        # of most populated
        response = get_rest("apps")
        response["title"] = "Apps by category"
    response["error"] = error
    return render_template("apps.html", **response)


@app.route("/apps/review", methods=['GET', 'POST'])
def write():
    """Show summary of apps by topic or individual apps depending on request.

    At the top level show tag category summaries.
    At the app level show reviews in descending date order.
    Otherwise show  individual app summaries within the topic.
    """
    error = None
    if request.method == 'POST':
        pass
    else:
        pass
    if 'tags' in request.form:
        pass
    else:
       pass 
    return render_template("write.html", title="Write a review",
                error=error)

@app.route("/profile", methods=['GET', 'POST'])
def profile():
    """Show summary of apps by topic or individual apps depending on request.

    At the top level show tag category summaries.
    At the app level show reviews in descending date order.
    Otherwise show  individual app summaries within the topic.
    """
    error = None
    # request items:
    #    avatar_data
    # response items:
    #    nickname
    #    avatar_location
    #    start_date
    #    
    return render_template("profile.html", title="Your profile",
                error=error)

@app.route("/providers", methods=['GET', 'POST'])
def providers():
    """List providers.
    """
    error = None
    return render_template("providers.html", title="Find a healthcare provider",
                error=error)

@app.route("/login", methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        if request.form['nickname'] != app.config['USERNAME']:
            error = 'Invalid username'
        elif request.form['password'] != app.config['PASSWORD']:
            error = 'Invalid password'
        else:
            session['logged_in'] = True
            flash('You were logged in')
            return redirect(url_for('show_entries'))
    return render_template('login.html', error=error)


if __name__ == "__main__":
    app.run() #debug=conf.DEBUG)

