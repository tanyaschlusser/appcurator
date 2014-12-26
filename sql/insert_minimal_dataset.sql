/* 
   --- APP TABLES ---             ||    --- USER TABLES ---
 public | device                  || 
 public | tag                     ||  public | patient_details
 public | organization_details    ||  public | patient_professional
 public | app                     ||  public | professional_organization
 public | app_device              ||  public | organization_admin
 public | app_links               ||  public | session_lookup
 public | app_platform            ||  public | user_details
 public | app_recommendation      ||  public | user_hierarchy
 public | app_review              ||  public | user_role
 public | app_tag
 public | platform

*/

/*====================== USER TABLES ==============================*/
/* -------------------------------- for "organization_details" --- */
INSERT INTO organization_details (organization_name)
  VALUES ('USA App Developers'), ('USA Health Providers');


/* ---------------------------------------- for "user_details" --- 
 * ---  And also "user_hierarchy", "user",                     ---
 * ---  "organization_admin", "professional_organization",     ---
 * ---  "patient_professional"                                 ---
 * --------------------------------------------------------------- */

/*INSERT INTO user_details (first_name, last_name, avatar, nickname)
  VALUES ();
*/
\COPY staging.user_details_loader (first_name, last_name, nickname, avatar, roles, organization_name, is_organization_admin, authorized_professionals, authorized_subs) FROM 'minimal_user_details.csv' WITH (FORMAT csv, NULL '', HEADER)
;

/* ------------------------------------- for 'patient_details' --- */
/* Not using patient_details right now but keeping them for later.
     The intent is a table like:
      user_id  facebook_uri    current_feeling
      -------  ------------    ---------------
      <id>     <url>           <'good' 'bad' or 'ok'>
 */


/*======================= APP TABLES ==============================*/
/* ---------------------------------------------- for "device" --- */
INSERT INTO device (device) VALUES ('Fitbit'), ('Nike+FuelBand');

/* -------------------------------------------- for "platform" --- */
INSERT INTO platform (platform) VALUES ('iOS'), ('Android'),('Tablet'),('Phone');

/* ------------------------------------------------- for "tag" --- */
SELECT insert_tag ('Sports', NULL);
SELECT insert_tag ('Mind and Meditation', NULL);
SELECT * FROM tag;
SELECT insert_tag ('Athletics', 'Sports');
SELECT insert_tag ('Track', 'Athletics');
SELECT insert_tag ('Swimming', 'Sports');
SELECT insert_tag ('Skiing', 'Sports');
SELECT insert_tag ('Karate', 'Sports');
SELECT insert_tag ('Luge', 'should fail');
SELECT insert_tag ('Luge', 'Sports');
SELECT insert_tag ('Sports', 'should fail');
SELECT * FROM tag;

--  Look at the tag hierarchy using category names.
SELECT p.category_name, s.category_name
FROM cat_to_parents AS a
LEFT JOIN tag AS p
  ON a.parent_category_id = p.category_id
JOIN tag as s
  ON a.category_id = s.category_id;

/* ---------------------------------- for "app" via "app_view" --- */
-- OK to INSERT into a view but COPY does not work.
--  For this, a trigger was added to the insert to get the
--  organization_id given the organization_name (because 'app' uses the org ID)
INSERT INTO app_view (app_name, organization_name, icon, objective)
  VALUES
('Free Throw Tracker',
  'USA App Developers',
  'BasketTracker.jpg',
    'Keep track of your free throw records, post videos showing your best run, and compete against your friends!'), 
('Kick Perfect','USA App Developers','KickCounter.jpg','Superimpose a master''s kick poses on your own.');

/* --- for "app", "app_platform", "app_device", "app_tag" via "staging.app_view_loader" --- */
-- For bulk loading, use the staging.app_view_loader table: it triggers
-- an INSERT function that matches organization names to org ids.
\COPY staging.app_view_loader (app_name, tags, organization_name, icon, objective, platforms, devices) FROM 'minimal_app_view.csv' WITH (FORMAT csv, NULL '', HEADER)
;


/* ------------------------------------------- for 'app_links' --- */
/* Not using app_links right now but keeping them for later.
     The intent is a table like:
      app_id  link_coded    link
      ------  ----------    ----
      <id>    <url>         <text for the url>
 */

/* ---------------------------------- for 'app_recommendation' --- */
-- app_id, recipient_id, recommender_id
INSERT INTO staging.app_recommendation_loader (app_name, recommender_nickname, recipient_nickname)
  VALUES
('Jog Route Tracker','valentina','tanya'),
('Laughter is the Best Medicine','valentina','ivy'),
('Laughter is the Best Medicine','doctor','valentina'),
('Laughter is the Best Medicine','doctor','ivy');

/* ------------------------------------------ for 'app_review' --- */
-- app_id, user_id, user_role, usability, effectiveness, review, platform_id
INSERT INTO staging.app_review_loader (app_name, user_nickname, user_role, usability, effectiveness, review, platform)
  VALUES
('Free Throw Tracker','valentina','user','good','ok','The UI was ok to use, but I didn''t get better after a month.','iOS'),
('Free Throw Tracker','tanya','user','ok','ok','I lost motivation after about 3 plays, but the UI was pretty easy to use.','iOS'),
('Kick Perfect','valentina','user','ok','good','Awesome app if only we could line up the pictures better.','iOS'),
('Kick Perfect','tanya','user','ok','good','Good app but hard to line up the pictures, especially if you''re short.','Android'),
('Laughter is the Best Medicine','doctor','health provider','good','good','This app has materially improved my patients'' mood score and reduced their dependence on drugs. Highly recommended.',NULL),
('Laughter is the Best Medicine','valentina','user','good','good','A quick easy way to brighten your day.','Android'),
('Laughter is the Best Medicine','appmaker','user','good','good','Free and fabulous.','Phone'),
('Meditation for Healing','appmaker','user','good','good','This is the best app for meditation.',NULL),
('Jog Route Tracker','doctor','health provider','ok','ok','About half of my patients stick with this -- various reasons for quitting include boredom or some difficulty with the UI.',NULL),
('Jog Route Tracker','nurse','health provider','good','ok','Very easy to use on the iOS','iOS'),
('Jog Route Tracker','valentina','user','ok','ok','Not good for using on the tablet, but OK for a small phone.','Phone'),
('Ski Better','valentina','user','ok','good','Hard to use but really informative.','iOS'),
('Swim Workout Time Split Tracker','doctor','health provider','ok','ok','Patients who work out in groups found this motivational but required training to use the app.',NULL),
('Swim Workout Time Split Tracker','valentina','user','ok','good','I loved competing and collaborating with old swim team friends across the country, but the UI could be easier.','Android');


