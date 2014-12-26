/*
 * create_views.sql
 *
 * Views on the tables made in create_tables.sql,
 * to simplify the queries made from the application.
 *
 */

/* Simple view for insertion of both organzation and app data. */
CREATE OR REPLACE VIEW app_view AS
  SELECT app_name, organization_name, icon, objective
  FROM app
  JOIN organization_details AS o
    ON app.organization_id = o.organization_id
;


CREATE OR REPLACE FUNCTION trigger_app_view() RETURNS TRIGGER
AS $trigger_app_view$
  DECLARE
    rows_matching integer;
    matching_org_id integer;
   BEGIN

      SELECT COUNT(1) INTO rows_matching
      FROM organization_details
      WHERE organization_name = NEW.organization_name;

      IF ( rows_matching = 0) THEN
        RAISE EXCEPTION 'No organization: %', NEW.organization_name;
      END IF;

      IF (TG_OP = 'INSERT') THEN
        INSERT INTO app (app_name, organization_id, icon, objective)
          VALUES(NEW.app_name, matching_org_id, NEW.icon, NEW.objective);
      END IF;

    RETURN NEW;
      
    END;
$trigger_app_view$
LANGUAGE plpgsql;

CREATE TRIGGER app_view_insertion_trigger
INSTEAD OF INSERT ON app_view
  FOR EACH ROW EXECUTE PROCEDURE trigger_app_view();



/* Map app_id to the device string. */
CREATE OR REPLACE VIEW app_device_view AS
  SELECT app_id, device
  FROM app_device AS ad
  JOIN device AS d
    ON ad.device_id = d.device_id
;

/* Map app_id to the platform string. */
CREATE OR REPLACE VIEW app_platform_view AS
  WITH distinct_platforms AS (
    SELECT DISTINCT app_id, platform_id
    FROM app_review)
  SELECT dp.app_id, platform
  FROM distinct_platforms AS dp
  JOIN platform AS ap
    ON dp.platform_id = ap.platform_id
;


/* Map all parent tags to all descendant tags. */
CREATE OR REPLACE VIEW cat_to_parents AS
  WITH RECURSIVE q AS (
    SELECT parent_category_id, category_id
      FROM tag
      WHERE parent_category_id IS NULL
    UNION
    SELECT t.parent_category_id, t.category_id
      FROM tag t
      JOIN q ON q.category_id = t.parent_category_id
  )
  SELECT * FROM q
;

/* Map app_id to all tags and parent tags. */
CREATE OR REPLACE VIEW app_category_view AS
  WITH intermediate AS (
      SELECT DISTINCT app_id, category_id
        FROM app_tag
      UNION
      SELECT DISTINCT
        app_id,
        ctp.parent_category_id AS category_id
        FROM app_tag AS at
        JOIN cat_to_parents AS ctp
          ON at.category_id = ctp.category_id
  )
  SELECT DISTINCT app_id, category_name
    FROM intermediate
    JOIN tag ON intermediate.category_id = tag.category_id
;

/* Map all parent tags to all descendant tags */
CREATE OR REPLACE VIEW app_summaries AS 
  WITH recs AS (
    SELECT app_id,
           COUNT(app_id) AS recommendations,
           COUNT(DISTINCT recommender_id) AS recommenders
    FROM app_recommendation
    GROUP BY app_id
  ), user_review AS (
    SELECT app_id,
    SUM( CASE WHEN usability = 'bad' THEN 1.0
              WHEN usability = 'ok' THEN 2.0
              ELSE 3.0
          END ) / COUNT( usability ) AS avg_usability, 
    SUM( CASE WHEN effectiveness = 'bad' THEN 1.0
              WHEN effectiveness = 'ok' THEN 2.0
              ELSE 3.0
         END ) / COUNT ( effectiveness ) AS avg_effectiveness
    FROM app_review
    WHERE user_role = 'user'
    GROUP BY app_id
  ), provider_review AS (
    SELECT app_id,
    SUM( CASE WHEN usability = 'bad' THEN 1.0
              WHEN usability = 'ok' THEN 2.0
              ELSE 3.0
          END ) / COUNT( usability ) AS avg_usability, 
    SUM( CASE WHEN effectiveness = 'bad' THEN 1.0
              WHEN effectiveness = 'ok' THEN 2.0
              ELSE 3.0
         END ) / COUNT ( effectiveness ) AS avg_effectiveness
    FROM app_review
    WHERE user_role = 'health provider'
    GROUP BY app_id
  ), last_review AS (
    SELECT app_id,
    MAX (review_date) AS last_review_date
    FROM app_review
    GROUP BY app_id
  ), devices AS (
    SELECT app_id,
      string_agg(device, '|') AS devices
    FROM app_device_view
    GROUP BY app_id
  ), platforms AS (
    SELECT app_id,
      string_agg(platform, '|') AS platforms
    FROM app_platform_view
    GROUP BY app_id
  ), categories AS (
    SELECT app_id,
      string_agg(category_name, '|') AS categories
    FROM app_category_view
    GROUP BY app_id
  )
  SELECT app.app_id, app_name, organization_name, icon, objective,
        CASE WHEN recommendations IS NULL THEN 0 ELSE recommendations END AS recommendations,
        CASE WHEN recommenders IS NULL THEN 0 ELSE recommenders END AS recommenders,
        u.avg_usability AS user_usability,
        p.avg_usability AS provider_usability,   
        u.avg_effectiveness AS user_effectiveness,
        p.avg_effectiveness AS provider_effectiveness,
        l.last_review_date,
        d.devices,
        pl.platforms,
        c.categories
  FROM app
  JOIN organization_details AS o
    ON app.organization_id = o.organization_id
  LEFT JOIN recs
    ON app.app_id = recs.app_id
  LEFT JOIN user_review AS u
    ON app.app_id = u.app_id
  LEFT JOIN provider_review AS p
    ON app.app_id = p.app_id
  LEFT JOIN devices AS d
    ON app.app_id = d.app_id
  LEFT JOIN platforms AS pl
    ON app.app_id = pl.app_id
  JOIN categories AS c
    ON app.app_id = c.app_id
  LEFT JOIN last_review AS l
    ON app.app_id = l.app_id
;


/* Combine the app and recommender names and images with recommender. */
CREATE OR REPLACE VIEW recommendation_view AS 
  SELECT app.app_id, app_name, icon,
      urecip.nickname AS recipient_nickname,
      urecc.nickname AS recommender_nickname,
      urecip.user_id AS recipient_id,
      urecc.user_id AS recommender_id,
      to_char(recc_date, 'FMDD Mon YYYY') as recc_date,
      to_char(received_date, 'FMDD Mon YYYY') as received_date,
      was_received
  FROM app_recommendation AS ar
  JOIN app
    ON ar.app_id = app.app_id
  JOIN user_details AS urecip
    ON ar.recipient_id = urecip.user_id
  JOIN user_details AS urecc
    ON ar.recommender_id = urecip.user_id
;

/* Just the top level tags and their top 3 reviews. */
CREATE OR REPLACE VIEW top_tags_view AS
   WITH tag_apps AS (
        SELECT DISTINCT tag.category_name, app_id
        FROM app_category_view AS acv
        JOIN tag
            ON tag.category_name = acv.category_name
        WHERE tag.parent_category_id IS NULL
    ), app_cts AS (
        SELECT category_name, COUNT(DISTINCT app_id) as act
        FROM tag_apps
        GROUP BY category_name
    ), review_cts AS (
        SELECT app_review.app_id, COUNT(DISTINCT review) as rct
        FROM app_review
        LEFT JOIN tag_apps
            ON app_review.app_id = tag_apps.app_id
        GROUP BY app_review.app_id,  tag_apps.app_id
    ), ranked_apps AS (
        SELECT category_name, r.app_id,
            row_number() OVER
                (PARTITION BY category_name ORDER BY rct DESC) AS i
        FROM review_cts AS r
        LEFT JOIN tag_apps AS t
            ON t.app_id = r.app_id
    )
    SELECT ranked_apps.category_name, app_id, act AS app_counts
    FROM ranked_apps
    JOIN app_cts
    ON ranked_apps.category_name = app_cts.category_name
    WHERE i <= 3
;

/* Add reviewer details and platform to the review. */
CREATE OR REPLACE VIEW review_view AS
  SELECT app_name, icon, nickname, avatar, user_role,
    CASE WHEN usability = 'bad' THEN 1.
        WHEN usability = 'ok' THEN 2.
        ELSE 3.  END AS usability,
    CASE WHEN effectiveness = 'bad' THEN 1.
        WHEN effectiveness = 'ok' THEN 2.
        ELSE 3.  END AS effectiveness,
    review,
    review_date,
    platform
  FROM app_review AS ar
  JOIN platform AS ap
    ON ar.platform_id = ap.platform_id
  JOIN user_details AS u
    ON ar.user_id = u.user_id
  JOIN app
    ON ar.app_id = app.app_id
;
