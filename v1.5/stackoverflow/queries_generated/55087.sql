-- {"query": "55087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1588} 

-- Benchmark query: heavy use of CTEs, window functions, JSON aggregation and multiple joins
WITH
-- 1. Core user activity aggregates
user_agg AS (
    SELECT
        u.id                                    AS user_id,
        u.displayname                           AS display_name,
        u.reputation,
        EXTRACT(YEAR FROM u.creationdate)       AS join_year,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        SUM(p.score) FILTER (WHERE p.posttypeid = 2) AS answer_score_sum,
        COUNT(CASE WHEN p.acceptedanswerid IS NOT NULL THEN 1 END) AS accepted_answer_cnt,
        COUNT(b.id)                             AS badge_cnt,
        COUNT(v.id) FILTER (WHERE v.votetypeid = 2) AS upvote_cnt,
        COUNT(v.id) FILTER (WHERE v.votetypeid = 3) AS downvote_cnt,
        MAX(p.lastactivitydate)                AS last_activity
    FROM users u
    LEFT JOIN posts p  ON p.owneruserid = u.id
    LEFT JOIN badges b ON b.userid = u.id
    LEFT JOIN votes v  ON v.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation, join_year
),

-- 2. Reputation change ranking per cohort (join year)
rep_rank AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (PARTITION BY join_year
                           ORDER BY reputation DESC) AS rep_rank_within_year
    FROM user_agg ua
),

-- 3. Recent post‑history actions per user (last 5 revisions)
recent_history AS (
    SELECT
        ph.userid,
        jsonb_agg(
            jsonb_build_object(
                'post_id', ph.postid,
                'type_id', ph.posthistorytypeid,
                'created', ph.creationdate,
                'comment', ph.comment
            )
            ORDER BY ph.creationdate DESC
        ) FILTER (WHERE ph.creationdate >= now() - interval '30 days') AS recent_changes
    FROM posthistory ph
    GROUP BY ph.userid
),

-- 4. Duplicate links created by the user (both directions)
duplicate_links AS (
    SELECT
        p.owneruserid                                      AS user_id,
        jsonb_agg(
            jsonb_build_object(
                'post_id', pl.postid,
                'duplicate_of', pl.relatedpostid,
                'created', pl.creationdate
            )
            ORDER BY pl.creationdate DESC
        )                                                 AS dup_links_out,
        jsonb_agg(
            jsonb_build_object(
                'post_id', pl.relatedpostid,
                'duplicate_of', pl.postid,
                'created', pl.creationdate
            )
            ORDER BY pl.creationdate DESC
        ) FILTER (WHERE pl.linktypeid = 3)                AS dup_links_in
    FROM postlinks pl
    JOIN posts p ON p.id = pl.postid
    WHERE pl.linktypeid = 3               -- duplicate link type
    GROUP BY p.owneruserid
),

-- 5. Tag usage stats for the user’s questions
user_tags AS (
    SELECT
        p.owneruserid                              AS user_id,
        jsonb_object_agg(tag, cnt) AS tag_distribution
    FROM (
        SELECT
            p.owneruserid,
            unnest(string_to_array(trim(both '<>' from p.tags), '><')) AS tag,
            COUNT(*) AS cnt
        FROM posts p
        WHERE p.posttypeid = 1                      -- only questions
        GROUP BY p.owneruserid, tag
    ) t
    GROUP BY t.owneruserid
)

SELECT
    rr.user_id,
    rr.display_name,
    rr.reputation,
    rr.join_year,
    rr.question_cnt,
    rr.answer_cnt,
    rr.answer_score_sum,
    rr.accepted_answer_cnt,
    rr.badge_cnt,
    rr.upvote_cnt,
    rr.downvote_cnt,
    rr.last_activity,
    rr.rep_rank_within_year,
    rh.recent_changes,
    dl.dup_links_out,
    dl.dup_links_in,
    ut.tag_distribution
FROM rep_rank rr
LEFT JOIN recent_history rh   ON rh.userid = rr.user_id
LEFT JOIN duplicate_links dl  ON dl.user_id = rr.user_id
LEFT JOIN user_tags ut        ON ut.user_id = rr.user_id
WHERE rr.rep_rank_within_year <= 10          -- top‑10 per cohort
ORDER BY rr.join_year, rr.rep_rank_within_year;
