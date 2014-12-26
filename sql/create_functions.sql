/*
 * create_functions.sql
 *
 * Functions on the tables made in create_tables.sql,
 * to simplify the queries made from the application.
 *
 */
CREATE OR REPLACE FUNCTION
  get_reviews(integer) RETURNS TABLE (
      nickname varchar,
      avatar varchar,
      platform varchar,
      user_role role,
      usability int,
      effectiveness int,
      review varchar,
      review_date varchar,
      app_name varchar,
      icon varchar
      ) AS $$

  SELECT nickname, avatar, platform, user_role,
    CASE WHEN usability = 'bad' THEN 1
         WHEN usability = 'ok' THEN 2
         ELSE 3
    END AS usability,
    CASE WHEN effectiveness = 'bad' THEN 1
         WHEN effectiveness = 'ok' THEN 2
         ELSE 3
    END AS effectiveness,
    review,
    to_char(review_date, 'FMDD Mon YYYY') as review_date,
    app_name,
    icon
  FROM app_review AS ar
  JOIN user_details AS u
    ON u.user_id = ar.user_id
  LEFT JOIN platform AS p
    ON p.platform_id = ar.platform_id
  JOIN app AS a
    ON a.app_id = ar.app_id
  WHERE ar.app_id = $1
  ORDER BY ar.review_date DESC;

$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION
  get_authorized_users(integer) RETURNS SETOF integer AS $$

  WITH RECURSIVE q AS (
      SELECT parent_id, sub_id
        FROM user_hierarchy
        WHERE parent_id = $1
      UNION
      SELECT uh.parent_id, uh.sub_id
        FROM user_hierarchy uh
        JOIN q ON q.sub_id = uh.parent_id
  )
  SELECT sub_id FROM q AS answer;

$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION
  insert_tag(varchar, varchar) RETURNS BOOLEAN AS $$

  DECLARE
    cid integer;
    success BOOLEAN;
  BEGIN
      success := FALSE;
      IF $2 IS NOT NULL THEN
        IF (SELECT count(1) FROM tag WHERE category_name = $2) > 0 THEN
          SELECT category_id INTO cid FROM tag WHERE category_name = $2 LIMIT 1;
          INSERT INTO tag (category_name, parent_category_id)
          VALUES ($1, cid);
          success := TRUE;
        END IF;
      ELSE
        INSERT INTO tag (category_name) VALUES ($1);
        success := TRUE;
      END IF;
      RETURN success ;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN FALSE;
    WHEN UNIQUE_VIOLATION THEN
      RETURN FALSE;
  END;

$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION
  is_authorized_for(integer) RETURNS SETOF integer AS $$

  WITH RECURSIVE q AS (
      SELECT parent_id, sub_id
        FROM user_hierarchy
        WHERE sub_id = $1
      UNION
      SELECT uh.parent_id, uh.sub_id
        FROM user_hierarchy uh
        JOIN q ON q.parent_id = uh.sub_id
  )
  SELECT parent_id FROM q AS answer;

$$ LANGUAGE SQL;
