#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# appcurator.py
"""
First attempt at showing database contents online. Does not
truly incorporate logins. Does not incorporate REST.

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
import pg8000  # Postgres database (we are using 9.3)

from flask import abort, flash, Flask, g, jsonify
from flask import redirect, render_template, request, session, url_for
from flask.views import MethodView
from jinja2 import Environment, Template

## Local configuration settings -- database connection, passwords
try:
    import configuration as conf
except ImportError:
    # Heroku wants us to use environment variables instead.
    class conf:
        @staticmethod
        def connect_db():
            return pg8000.connect(
                    database=os.environ['DATABASE'],
                    host=os.environ['HOST'],
                    port=int(os.environ['PORT']),
                    user=os.environ['USER'],
                    password=os.environ['PASSWORD'],
                    ssl=True
                    )

        @staticmethod
        def reset_db():
            with closing(connect_db()) as db:
                with open('sql/drop_tables.sql', 'r') as f:
                    db.cursor().execute(f.read())
                with open('sql/create_tables.sql', 'r') as f:
                    db.cursor().execute(f.read())
                db.commit()

    

## Setup
app = Flask(__name__)
app.config["STATIC_DIR"] = os.path.join(
            os.path.dirname(os.path.realpath(__file__)),
            'static')
app.config["AVATAR_DIR"] = "images/avatars/"
app.config["ICON_DIR"] = "images/icons/"

env = Environment()
env.globals["session"] = session  # Makes session available for the template.


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
    """Return the result of a select query as an array of dictionaries.

    Each dictionary has keys taken from the 'columns' argument, or else
    'col0' ... 'colN-1' for the N columns returned.

    If there is an error with the query, return None.

    Keyword arguments
    args -- passed to pg8000.cursor.execute() for a secure
            parameterized query.
            We use the default format: SELECT * FROM TABLE WHERE col1 = '%s'
    """
    cur = db_query(query, args=args) 
    if cur is None:
        return None
    try:
        results = cur.fetchall()
    except pg8000.ProgrammingError as e:
        get_db().rollback()
        cur.close()
        return None
    cur.close()
    if len(results) == 0:
        return None
    elif len(results[0]) > len(columns):
        columns = list(columns) + ["col%d" % i for i in range(len(columns),len(results))]
    elif len(results[0]) < len(columns):
        columns = columns[0:len(results[0])]

    return [dict(zip(columns, result)) for result in results]


def db_select_one(query, args=None, columns=None):
    """Return the one-row result of a select query as a dictionary.

        If there are more than one rows, return only the contents of the first one.
        If there are no rows, return None.
    """
    rows = db_select(query, args=args, columns=columns)
    if rows is None or len(rows) == 0:
        return {}
    return rows[0]


## ---------------------------------------------------- Login parts ----- ##
# This section will handle communication with Facebook to
# confirm the identity of the individual logging in, once
# we use Facebook's Open ID service.
def confirm_user_identity(userid, token=None):
    """Confirm via Facebook that the user is who s/he says.

    Will follow instructions here:
        https://developers.facebook.com/docs/facebook-login/access-tokens/
        https://developers.facebook.com/docs/facebook-login/login-flow-for-web/v2.2
    """
    return True

def is_logged_in(userid):
    """Confirm via the session_lookup table that this user is logged in.
    """
    return True

## -------------------------------------------- False RESTful parts ----- ##
# This section will later be moved to a module devoted to serving
# a RESTful API. It will be replaced by modified versions of
# get_rest() and post_rest(), which will query the RESTful API
# rather than send off to different functions here.
#
# The functions all take key,value pairs (**kwargs)
# and return dictionaries that could be converted to valid JSON
def delete_nulls_arr(a):
    map(lambda row:[row.pop(k) for k in row.keys() if row[k] is None], a)

def delete_nulls_dict(d):
    [d.pop(k) for k in d.keys() if d[k] is None]

def get_apps(appid=None, tags=None, **kwargs):
    """
    Respond to a REST query at /apps.

    If there is an appid, return all its reviews, plus the one app summary:
         reviews: [{nickname:, avatar:, platform:, user_role:, usability:,
                    effectiveness:, review:, review_date:} ]

    If there are any tags, return summaries for all apps with those tags:
        app_summaries: [{name:, icon:, organization:, objective:,
                         categories:[],  devices:[], platforms:[],
                         link_entries:[], n_recc:, n_users:,
                         provider_usability:, user_usability:,
                         provider_effectiveness:, user_effectiveness:,
                         last_review_date: }]

    If there are no tags or appid, return summaries for all top-level tags,
    with the top three (in number of reviews) app summaries:
        tag_summaries: [{name:, n_apps:, top_apps:[app_summaries]}]
    """
    result = dict(error=None)
    starter_query = """
                SELECT app_id, app_name, icon, organization_name,
                    objective, recommendations, recommenders,
                    user_usability, provider_usability,
                    user_effectiveness, provider_effectiveness,
                    to_char(last_review_date, 'FMDD Mon YYYY'),
                    categories, devices, platforms
                FROM app_summaries
            """
    starter_columns = ["app_id", "name", "icon", "organization",
            "objective", "n_recc", "n_users",
            "user_usability", "provider_usability",
            "user_effectiveness", "provider_effectiveness",
            "last_review_date", "categories", "devices", "platforms"]
    app_summaries = []
    tag_summaries = None
    if appid is not None:
        app_summaries = db_select( starter_query +
                " WHERE app_id = %s;",
                args=[appid],
                columns=starter_columns)
        app_summaries[0]["hasreviews"] = True
        result["reviews"] = db_select( """
                SELECT nickname, avatar, platform, user_role,
                    usability, effectiveness, review, review_date
                FROM get_reviews(%s);
                """,
                args=[appid],
                columns=[ "nickname", "avatar", "platform", "user_role",
                    "usability", "effectiveness", "review", "review_date"])
        for review in result["reviews"]:
            pass
    elif tags is not None:
        # Show the apps for the requested tags only.
        tags = [t.lower() for t in tags]
        slots = ", ".join(["%s"] * len(tags))
        app_summaries = db_select(
                """WITH tag_ids AS (
                   SELECT app_id AS tag_app_id
                   FROM app_category_view
                   WHERE category_name IN (%s) ) 
                """ % slots +
                starter_query +
                """ AS summ JOIN tag_ids ON
                    summ.app_id = tag_ids.tag_app_id;
                """,
                args = tags,
                columns=starter_columns)

    if len(app_summaries)==0 or (appid is None and tags is None):
        # Show the top few tags, with brief snapshots
        # of the apps per tag.
        tag_rows = db_select("""
                SELECT category_name, app_id, app_counts FROM top_tags_view;
                """,
                columns=["name", "app_id", "n_apps"])
        tag_summaries = {}
        app_ids = set()
        for row in tag_rows:
            tag_summaries.setdefault(row['name'],
                    { 'name': row['name'],
                      'n_apps': row['n_apps'],
                      'top_apps_set': set() })['top_apps_set'].add(row['app_id'])
            app_ids.add(row['app_id']) 
        tag_summaries = [v for v in tag_summaries.values()]
               
        slots = ", ".join(["%s"] * len(app_ids)) 
        app_summaries = db_select(
                starter_query + " WHERE app_id IN (%s);" %slots,
                args=app_ids,
                columns=starter_columns)
    if app_summaries is not None:
        # The 'categories', 'devices', 'platforms' (and eventually the links
        # come back as pipe-joined strings rather than as lists.
        # Break them apart into lists.
        if len(app_summaries) > 0:
            for summary in app_summaries:
                for key in ('categories', 'devices', 'platforms'):
                    summary[key] = summary[key].split("|") if summary[key] is not None else []
        delete_nulls_arr(app_summaries)

    # Either we will present tag summaries or app summaries.
    # Put the correct variable in the result...
    if tag_summaries is not None: 
        # Map each app summary to its respective tag(s).
        app_summaries = dict((row['app_id'],row) for row in app_summaries)
        for entry in tag_summaries:
            entry['top_apps'] = [app_summaries[appid] for appid in entry['top_apps_set']]
        result["tag_summaries"] = tag_summaries 
    else:
        result["app_summaries"] = app_summaries

    return result


def get_login(nickname=None, **kwargs):
    result = {}
    if nickname is None:
        result["error"]["nickname"] = "No user name given."
    else:
        result = db_select_one(
                "SELECT nickname, user_id, avatar FROM user_details WHERE nickname=%s;",
                args=[nickname.lower()],
                columns=["nickname", "user_id", "avatar"])
        if result is None: 
            result = {"error":"Username not found."}
    return result


def get_profile(nickname="", **kwargs):
    update = {}
    result = dict(error = None,
        nickname=nickname,
        avatar="default.png" )

    if nickname != "" and nickname is not None:
        update = db_select_one("""
                SELECT nickname, avatar, first_name, last_name,
                       to_char(start_date, 'Month YYYY') AS start_date
                FROM user_details
                WHERE nickname = %s;""",
                args=[nickname],
                columns=["nickname", "avatar",
                    "first_name", "last_name", "start_date"])

        update['recommended_by_list'] = db_select(
                """SELECT
                    app_name, icon,
                    recipient_nickname AS name
                   FROM recommendation_view
                    WHERE recommender_nickname = %s;""",
                args=[nickname],
                columns=["app", "icon", "name"])    

        update['recommended_to_list'] = db_select(
                """SELECT
                    app_name, icon,
                    recommender_nickname AS name
                   FROM recommendation_view
                    WHERE recipient_nickname = %s;""",
                args=[nickname],
                columns=["app", "icon", "name"])

        update['review_list'] = db_select(
                """SELECT
                app_name, icon, review_date, review
                FROM user_details AS ud
                JOIN app_review AS ar
                    ON ar.user_id = ud.user_id
                JOIN app
                    ON ar.app_id = app.app_id
                WHERE ud.nickname = %s;""",
                args=[nickname],
                columns=["app", "icon", "review_date", "review"])

        delete_nulls_dict(update)
    result.update(update)
    return result


def get_rest(path, query={}):
    """To be replaced by a query to a RESTful API later."""
    apis = {
        "apps": get_apps,
        "login": get_login,
        "profile": get_profile}
    if path in apis:
        print "(Get) Query:", query
        result = apis[path](**query)
        if isinstance(result, dict):
            delete_nulls_dict(result)
        print "(Get) Result:", result
        import sys
        sys.stdout.flush()
        return result
    else:
        return None


def post_login(nickname=None, **kwargs):
    result = {}
    if nickname is None:
        result["error"]["nickname"] = "No user name given."
    else:
        db_query("INSERT INTO user_details (nickname) VALUES (%s)",
                 args=[nickname.lower()],
                 commit=True)
        result = db_select_one("""
                SELECT nickname, user_id, avatar
                FROM user_details WHERE nickname=%s;
                """,
                args=[nickname.lower()],
                columns=["nickname", "user_id", "avatar"])
        if result is None: 
            result = {"error": "Sorry, username not found."}
    return result


def post_profile(nickname=None, **kwargs):
    """Update the user's profile.

    kwargs should contain first_name, last_name, image.
    Image is right now (Dec 2014) a werkzeug.datastructures.FileStorage
    object but should be converted for send/receive via RESTful API
    """
    if nickname != None:
        result = db_select_one(
                "SELECT user_id FROM user_details WHERE nickname = %s;",
                args=[nickname],
                columns=["user_id"])
        if result is not None:
            user_id = result["user_id"]
            if "avatar" in kwargs:
                avatar = "avatar_%d.jpg" % user_id
                kwargs['avatar'].save(os.path.join(
                    app.config['STATIC_DIR'],
                    app.config['AVATAR_DIR'],
                    avatar))
                kwargs['avatar'] = avatar

            QUERY = "UPDATE user_details SET {QUERY_TEXT} WHERE user_id=%d;" % user_id
            query_keys = ('first_name', 'last_name', 'avatar')
            query_text = ", ".join(("{k}=%s".format(k=k) for k in query_keys
                                    if k in kwargs))
            query_data =  [kwargs[k] for k in query_keys if k in kwargs]
    
            cur = db_query(QUERY.format(QUERY_TEXT=query_text),
                     args=query_data,
                     commit=True)

            if cur is not None:
                result = {"success" : True}
        else:
            result = {"error": "Username not found."}
    else:      
        result = {"error": "Username not given."}
    return result
            

def post_rest(path, query={}):
    """To be replaced by a query to a RESTful API later."""
    apis = {
        "login": post_login,
        "profile": post_profile}
    if path in apis:
        print "(Post) Query:", query
        result = apis[path](**query)
        delete_nulls_dict(result)
        print "(Post) Result:", result
        import sys
        sys.stdout.flush()
        return result
    else:
        return None
    

## ------------------------------------------------------ Web parts ----- ##
@app.route("/")
def index():
    """The main page is at /apps, so redirect."""
    return redirect(url_for('apps'))


@app.route("/about/")
def about():
    """About is a static page."""
    return render_template('about.html', title="About us")


@app.route("/apps/", methods=['GET', 'POST'])
@app.route("/apps/<appid>", methods=['GET', 'POST'])
def apps(appid=None):
    """Show summary of apps by topic or individual apps depending on request.

    At the top level show tag category summaries.
    At the app level show reviews in descending date order.
    Otherwise show  individual app summaries within the topic.
    """
    error = None
    kwargs = {}
    if appid is not None:
        kwargs['appid'] = int(appid)
    elif 'tags' in request.form:
        tags = [t.lower() for t in tag.strip().split()]
        response = {}
        response["title"] = "App"

    if 'review' in request.form:
        logged_in = is_logged_in()
        if logged_in:
            return redirect(url_for('write', appid=appid))
        else:
            return redirect(url_for('login'))
    else:
        # Show summaries of the topics, in descending order
        # of most populated
        # response = get_rest("apps", appid=xxx)
        # response = get_rest("apps", tagx=[yy,yyy,yyy])
        response = get_rest("apps", query=kwargs)
        
    response["error"] = error
    return render_template("apps.html", **response)


@app.route("/apps/review/", methods=['GET', 'POST'])
@app.route("/apps/<appid>/review/", methods=['GET', 'POST'])
def write(appid=None):
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

@app.route("/profile/", methods=['GET', 'POST'])
def profile():
    """Show and allow modification of a user's profile.

        post items:
           nickname, avatar_data, first_name, last_name
          
        get items:
           nickname, avatar,
           first_name, last_name, start_date
           recommended_by_list=[{name:name, app:app},  {name:name, app:app}]
           recommended_to_list=[{name:name, app:app},  {name:name, app:app}]
           review_list=[{review_date:dt, app:app},  {review_date:dt, app:app}]

    Also eventually allow users to identify health providers, and health
    providers to designate proxy providers (nurses or other assistants).
    """
    query = {}
    result = {}

    if request.method == 'GET':
        # GET -- If not logged in, ask user to log in else show the profile.
        print "Profile GET..."
        if 'user' not in session:
            result["error"] = "Oup! Please log in to see your profile."
        else:
            query["nickname"] = session["user"]["nickname"]
            

    elif request.method == 'POST':
        # POST -- If not logged in, show an error message asking
        #         the user to log in.
        #         Otherwise, get the changes and update them.
        print "Profile POST..."
        if "user" not in session:
            result["error"] = "Oup! Please log in to change your profile."
        else:
            print "The whole request.form:", request.form
            print "The files:", request.files

            fields = ("first_name", "last_name")
            for f in fields:
                if f in request.form:
                    query[f] = request.form[f]
            print "the query:", query
            if "image" in request.files:
                query["avatar"] = request.files["image"]

            query["nickname"] = session["user"]["nickname"]
            result = post_rest("profile", query=query)
                
    update = get_rest("profile", query=query)
    if update is not None:
        result.update(update)
        if 'user' in session:
            session['user']['avatar'] = result['avatar']
    return render_template("profile.html", **result)


@app.route("/providers/", methods=['GET', 'POST'])
def providers():
    """List providers.
    """
    error = None
    result = {}
    if error is not None:
        result["error"] = error
    if "user" in session:
        result["user"] = session["user"]
    return render_template("providers.html", **result)


@app.route("/login/", methods=['GET', 'POST'])
def login():
    result = {}
    if request.method == 'POST':
        query = {}
        if 'nickname' in request.form:
            query['nickname'] = request.form['nickname']
            result = get_rest("login", query=query)
            if "create" in request.form:
                if "error" not in result:
                    # The nickname is in use already
                    result = {
                        "error":
                        "Sorry, cannot create username -- already in use."}
                else:
                    # Then the nickname is available for use. Create it.
                    result = post_rest("login", query=query)
                    result["created"] = "true"
        else:
           result["error"] = "No user id entered."

        print "RESULT:", result
        if "user_id" in result:
            flash('Login successful')
            session['user'] = result
            
        return jsonify(**result)

    elif request.method == 'GET':
        return render_template('login.html')


@app.route('/logout/')
def logout():
    # remove the username from the session if it's there
    session.pop('user', None)
    flash('Logged out -- see you later!')
    return 'Logged out'


# app.secret_key is used by flask.session to encrypt the cookies
app.secret_key = os.urandom(24)



if __name__ == "__main__":
    app.run(debug=conf.DEBUG)

