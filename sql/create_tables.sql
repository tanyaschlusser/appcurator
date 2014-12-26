/* 
 * create_tables.sql
 *
 * We are using Postgres 9.3. This document creates all of
 * the tables that will be used in the database.
 *
 * The main point of the website is to allow both health
 * providers and patients to rate and review apps, and collaborate
 * about healthcare in the context of the app.
 */

CREATE TABLE IF NOT EXISTS user_details (
  user_id serial PRIMARY KEY,
  avatar varchar(64) DEFAULT 'default.png',
  nickname varchar(32) UNIQUE NOT NULL,
  first_name varchar(32),
  last_name varchar(32),
  start_date date NOT NULL DEFAULT current_date
);


CREATE TABLE IF NOT EXISTS session_lookup (
  session_start timestamp with time zone NOT NULL,
  facebook_user_id bigint UNIQUE NOT NULL,
  user_id int REFERENCES user_details (user_id)
);


CREATE TABLE IF NOT EXISTS user_hierarchy (
  parent_id int REFERENCES user_details (user_id),
  sub_id int REFERENCES user_details (user_id)
);


CREATE TABLE IF NOT EXISTS organization_details (
  organization_id serial PRIMARY KEY,
  organization_name varchar(64) UNIQUE NOT NULL,
  facebook_uri varchar(128)
);

CREATE TABLE IF NOT EXISTS app (
  app_id serial PRIMARY KEY,
  app_name varchar(128),
  organization_id int REFERENCES organization_details (organization_id),
  icon varchar(64) DEFAULT 'default.png',
  advertisement_text varchar(128),
  objective varchar(256) NOT NULL
);


CREATE TABLE IF NOT EXISTS app_links (
  app_id int REFERENCES app (app_id),
  link varchar(128) NOT NULL,
  link_code varchar(16) NOT NULL
);


CREATE TABLE IF NOT EXISTS tag (
  category_id SERIAL PRIMARY KEY,
  parent_category_id int REFERENCES tag (category_id),
  category_name varchar(128) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS app_tag (
  app_id int REFERENCES app (app_id) NOT NULL,
  category_id int REFERENCES tag(category_id)
);


CREATE TABLE IF NOT EXISTS app_recommendation (
  app_id int REFERENCES app (app_id) NOT NULL,
  recipient_id int REFERENCES user_details (user_id) NOT NULL,
  recommender_id int REFERENCES user_details (user_id) NOT NULL,
  recc_date date NOT NULL DEFAULT current_date,
  received_date date,
  was_received boolean NOT NULL DEFAULT FALSE
);


CREATE TABLE IF NOT EXISTS platform (
  platform_id serial PRIMARY KEY,
  platform varchar(128) NOT NULL
);


CREATE TABLE IF NOT EXISTS device (
  device_id serial PRIMARY KEY,
  device varchar(128) NOT NULL
);

CREATE TABLE IF NOT EXISTS app_device (
  app_id int REFERENCES app (app_id) NOT NULL,
  device_id int REFERENCES device (device_id) NOT NULL
);

CREATE TABLE IF NOT EXISTS app_platform (
  app_id int REFERENCES app (app_id) NOT NULL,
  platform_id int REFERENCES platform (platform_id) NOT NULL
);


CREATE TYPE role AS ENUM(
    'site administrator',
    'manufacturer',
    'health provider',
    'user');

CREATE TYPE evaluation AS ENUM(
    'bad',
    'ok',
    'good');


CREATE TABLE IF NOT EXISTS app_review (
  app_id int REFERENCES app (app_id) NOT NULL,
  user_id int REFERENCES user_details (user_id) NOT NULL,
  user_role role DEFAULT 'user',
  usability evaluation DEFAULT 'ok',
  effectiveness evaluation DEFAULT 'ok',
  review varchar(512),
  review_date date NOT NULL DEFAULT current_date,
  platform_id int REFERENCES platform (platform_id),
  CONSTRAINT unique_app_user_pairs UNIQUE (app_id, user_id)
);


CREATE TABLE IF NOT EXISTS user_role (
  user_id int REFERENCES user_details (user_id),
  role_code role NOT NULL
);

CREATE TABLE IF NOT EXISTS patient_details (
  user_id int REFERENCES user_details (user_id),
  facebook_uri varchar(128),
  current_feeling evaluation
);

CREATE TABLE IF NOT EXISTS patient_professional (
  patient_id int REFERENCES user_details(user_id),
  professional_id int REFERENCES user_details(user_id)
);

CREATE TABLE IF NOT EXISTS professional_organization (
  professional_id int REFERENCES user_details (user_id),
  organization_id int REFERENCES organization_details (organization_id)
);

CREATE TABLE IF NOT EXISTS organization_admin (
  user_id int REFERENCES user_details (user_id),
  organization_id int REFERENCES organization_details (organization_id)
);


/* ==================== STAGING TABLES AND TRIGGERS =================== */
CREATE SCHEMA IF NOT EXISTS staging;
CREATE TABLE IF NOT EXISTS staging.app_view_loader (
  app_name varchar(128) NOT NULL,
  organization_name varchar(64) NOT NULL,
  icon varchar(128) NOT NULL,
  objective varchar(256) NOT NULL,
  tags varchar(128)[],
  platforms varchar(128)[],
  devices varchar(128)[],
  load boolean DEFAULT TRUE
);

CREATE OR REPLACE FUNCTION trigger_app_view_loader() RETURNS TRIGGER
AS $trigger_app_view_loader$
   DECLARE
    current_app_id integer;
    matched_id integer;
    element varchar(128);
    r RECORD;
   BEGIN

      INSERT INTO app (app_name, organization_id, icon, objective) (
        SELECT app_name, organization_id, icon, objective
          FROM staging.app_view_loader AS avl
        JOIN organization_details AS od
          ON avl.organization_name = od.organization_name
        WHERE load = TRUE
      );

      -- Go row by row and insert into the respective correct dimensional tables.
      FOR r IN SELECT * FROM staging.app_view_loader WHERE load=TRUE LOOP
          SELECT max(app_id) INTO current_app_id FROM app WHERE r.app_name = app.app_name;

          -- app_platform
          IF (r.platforms  IS NOT NULL) THEN
            FOREACH element in ARRAY r.platforms
            LOOP
              SELECT platform_id INTO matched_id FROM platform AS pl WHERE pl.platform = element;

              IF (matched_id IS NOT NULL) THEN
                INSERT INTO app_platform(app_id, platform_id)
                  VALUES(current_app_id, matched_id);
              END IF;
            END LOOP;
          END IF;

          -- app_device
          IF (r.devices IS NOT NULL) THEN
            FOREACH element in ARRAY r.devices
            LOOP
              SELECT device_id INTO matched_id FROM device WHERE device.device = element;

              IF (matched_id IS NOT NULL) THEN
                INSERT INTO app_device(app_id, device_id)
                  VALUES(current_app_id, matched_id);
              END IF;
            END LOOP;
         END IF;

          -- app_tag
          IF (r.tags IS NOT NULL) THEN
            FOREACH element in ARRAY r.tags
            LOOP
              SELECT category_id INTO matched_id FROM tag WHERE tag.category_name = element;

              IF (matched_id IS NOT NULL) THEN
                INSERT INTO app_tag(app_id, category_id)
                  VALUES(current_app_id, matched_id);
              END IF;
            END LOOP;
         END IF;
      END LOOP;

      UPDATE staging.app_view_loader SET load = FALSE;
      RETURN NULL;

    END;
$trigger_app_view_loader$
LANGUAGE plpgsql;

CREATE TRIGGER app_view_loader_copy_trigger
  AFTER INSERT ON staging.app_view_loader
  EXECUTE PROCEDURE trigger_app_view_loader();



CREATE TABLE IF NOT EXISTS staging.app_recommendation_loader (
  app_name varchar(128) NOT NULL,
  recommender_nickname varchar(32) NOT NULL,
  recipient_nickname varchar(32) NOT NULL,
  load boolean DEFAULT TRUE
);

CREATE OR REPLACE FUNCTION trigger_app_recommendation_loader() RETURNS TRIGGER
AS $trigger_app_recommendation_loader$
   BEGIN

      INSERT INTO
        app_recommendation (app_id, recommender_id, recipient_id)
        (
        SELECT app_id, recc.user_id, recip.user_id
          FROM staging.app_recommendation_loader AS arl
        JOIN app
          ON arl.app_name = app.app_name
        JOIN user_details AS recc
          ON arl.recommender_nickname = recc.nickname
        JOIN user_details AS recip
          ON arl.recipient_nickname = recip.nickname
        WHERE load = TRUE
      );

      UPDATE staging.app_recommendation_loader SET load = FALSE;
      RETURN NULL;

    END;
$trigger_app_recommendation_loader$
LANGUAGE plpgsql;

CREATE TRIGGER app_recommendation_loader_copy_trigger
  AFTER INSERT ON staging.app_recommendation_loader
  EXECUTE PROCEDURE trigger_app_recommendation_loader();




CREATE TABLE IF NOT EXISTS staging.app_review_loader (
  app_name varchar(128) NOT NULL,
  user_nickname varchar(32) NOT NULL,
  user_role role,
  usability evaluation,
  effectiveness evaluation,
  review varchar(512),
  platform varchar(128),
  load boolean DEFAULT TRUE,
  unique(app_name, user_nickname)
);

CREATE OR REPLACE FUNCTION trigger_app_review_loader() RETURNS TRIGGER
AS $trigger_app_review_loader$
   BEGIN

      INSERT INTO
        app_review (app_id, user_id, user_role, usability, effectiveness, review, platform_id)
        (
        SELECT app_id, user_id, user_role, usability, effectiveness, review, platform_id
          FROM staging.app_review_loader AS arl
        JOIN app
          ON arl.app_name = app.app_name
        JOIN user_details AS ud
          ON arl.user_nickname = ud.nickname
        LEFT OUTER JOIN platform AS p
          ON arl.platform = p.platform
        WHERE load = TRUE
      );

      UPDATE staging.app_review_loader SET load = FALSE;
      RETURN NULL;

    END;
$trigger_app_review_loader$
LANGUAGE plpgsql;

CREATE TRIGGER app_review_loader_copy_trigger
  AFTER INSERT ON staging.app_review_loader
  EXECUTE PROCEDURE trigger_app_review_loader();


CREATE TABLE IF NOT EXISTS staging.user_details_loader (
  avatar varchar(512),
  nickname varchar(32) UNIQUE NOT NULL,
  first_name varchar(32),
  last_name varchar(32),
  roles role[],
  organization_name varchar(64),
  is_organization_admin boolean DEFAULT FALSE,
  authorized_professionals varchar(32)[],
  authorized_subs varchar(32)[],
  load boolean DEFAULT TRUE
);

CREATE OR REPLACE FUNCTION trigger_user_details_loader() RETURNS TRIGGER
AS $trigger_user_details_loader$
   DECLARE
    current_user_id integer;
    matched_id integer;
    element varchar(128);
    role_element role;
    r RECORD;
   BEGIN

      INSERT INTO user_details (avatar, nickname, first_name, last_name) (
        SELECT avatar, nickname, first_name, last_name
          FROM staging.user_details_loader AS udl
        WHERE load = TRUE
      );

      -- professional_organization
      INSERT INTO professional_organization (professional_id, organization_id) (
        SELECT user_id, organization_id
        FROM user_details AS ud
        JOIN staging.user_details_loader AS udl
          ON udl.nickname = ud.nickname
        JOIN organization_details AS od
          ON udl.organization_name = od.organization_name
        WHERE udl.load=TRUE );

      -- organization_admin
      INSERT INTO organization_admin (user_id, organization_id) (
        SELECT user_id, organization_id
        FROM user_details AS ud
        JOIN staging.user_details_loader AS udl
          ON udl.nickname = ud.nickname
        JOIN organization_details AS od
          ON udl.organization_name = od.organization_name
        WHERE udl.load=TRUE AND udl.is_organization_admin=TRUE);

      -- Go row by row and insert into the respective correct dimensional tables.
      FOR r IN SELECT * FROM staging.user_details_loader WHERE load=TRUE LOOP
          SELECT max(user_id) INTO current_user_id FROM user_details AS u WHERE r.nickname = u.nickname;

          -- user_role 
          IF (r.roles IS NOT NULL) THEN
            FOREACH role_element in ARRAY r.roles
            LOOP
              INSERT INTO user_role(user_id, role_code)
                VALUES(current_user_id, role_element);
            END LOOP;
          END IF;

          -- patient_professional
          IF (r.authorized_professionals IS NOT NULL) THEN
            FOREACH element in ARRAY r.authorized_professionals
            LOOP
              SELECT user_id INTO matched_id FROM user_details AS u WHERE u.nickname = element;

              IF (matched_id IS NOT NULL) THEN
                INSERT INTO patient_professional(patient_id, professional_id)
                  VALUES(current_user_id, matched_id);
              END IF;
            END LOOP;
         END IF;

          -- user_hierarchy
          IF (r.authorized_subs IS NOT NULL) THEN
            FOREACH element in ARRAY r.authorized_subs
            LOOP
              SELECT user_id INTO matched_id FROM user_details AS u WHERE u.nickname = element;

              IF (matched_id IS NOT NULL) THEN
                INSERT INTO user_hierarchy(parent_id, sub_id)
                  VALUES(current_user_id, matched_id);
              END IF;
            END LOOP;
         END IF;
      END LOOP;

      UPDATE staging.user_details_loader SET load = FALSE;
      RETURN NULL;

    END;
$trigger_user_details_loader$
LANGUAGE plpgsql;

CREATE TRIGGER user_details_loader_copy_trigger
  AFTER INSERT ON staging.user_details_loader
  EXECUTE PROCEDURE trigger_user_details_loader();

