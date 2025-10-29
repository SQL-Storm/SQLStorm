-- {"query": "3035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3164}
WITH
user_post_stats AS (
    SELECT
        u.id                                            AS user_id,
        u.displayname,
        u.reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1)      AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2)      AS answer_cnt,
        SUM(COALESCE(p.score,0))                        AS total_score,
        MAX(p.creationdate)                             AS last_post_dt
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

user_badge_stats AS (
    SELECT
        b.userid,
        COUNT(*) FILTER (WHERE b.class = 1)            AS gold_badge_cnt,
        COUNT(*) FILTER (WHERE b.class = 2)            AS silver_badge_cnt,
        COUNT(*) FILTER (WHERE b.class = 3)            AS bronze_badge_cnt,
        MAX(b.date)                                    AS last_badge_dt
    FROM badges b
    GROUP BY b.userid
),

post_vote_stats AS (
    SELECT
        p.owneruserid                                 AS user_id,
        COUNT(*) FILTER (WHERE v.votetypeid = 2)      AS upvote_cnt,
        COUNT(*) FILTER (WHERE v.votetypeid = 3)      AS downvote_cnt,
        SUM(CASE v.votetypeid WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS net_vote
    FROM votes v
    JOIN posts p ON p.id = v.postid
    GROUP BY p.owneruserid
),

user_vote_totals AS (
    SELECT
        user_id,
        SUM(upvote_cnt)       AS total_upvotes,
        SUM(downvote_cnt)     AS total_downvotes,
        SUM(net_vote)         AS total_netvotes
    FROM post_vote_stats
    GROUP BY user_id
),

user_close_reason AS (
    SELECT
        u.id                                          AS user_id,
        (SELECT COUNT(DISTINCT CAST(ph.comment AS INTEGER))
         FROM posthistory ph
         WHERE ph.posthistorytypeid = 10
           AND ph.userid = u.id)                      AS distinct_close_reason_cnt
    FROM users u
),

user_recent_activity AS (
    SELECT
        u.id                                          AS user_id,
        GREATEST(
            COALESCE(u.lastaccessdate,       TIMESTAMP '1970-01-01'),
            COALESCE(ups.last_post_dt,      TIMESTAMP '1970-01-01'),
            COALESCE(ubs.last_badge_dt,     TIMESTAMP '1970-01-01')
        )                                            AS last_active_dt
    FROM users u
    LEFT JOIN user_post_stats ups ON ups.user_id = u.id
    LEFT JOIN user_badge_stats ubs ON ubs.userid = u.id
    GROUP BY u.id, ups.last_post_dt, ubs.last_badge_dt, u.lastaccessdate
),

post_tags_exploded AS (
    SELECT
        p.id                                          AS post_id,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.tags), '><')) AS tag_name
    FROM posts p
    WHERE p.tags IS NOT NULL
),

tag_aggregates AS (
    SELECT
        pt.tag_name,
        COUNT(DISTINCT pt.post_id)                    AS post_cnt,
        SUM(COALESCE(p.score,0))                      AS tag_total_score,
        MAX(p.creationdate)                           AS most_recent_post_dt
    FROM post_tags_exploded pt
    JOIN posts p ON p.id = pt.post_id
    GROUP BY pt.tag_name
),

user_combined AS (
    SELECT
        ups.user_id,
        ups.displayname,
        ups.reputation,
        ups.question_cnt,
        ups.answer_cnt,
        ups.total_score,
        ups.last_post_dt,
        COALESCE(ubs.gold_badge_cnt,0)    AS gold_badge_cnt,
        COALESCE(ubs.silver_badge_cnt,0)  AS silver_badge_cnt,
        COALESCE(ubs.bronze_badge_cnt,0)  AS bronze_badge_cnt,
        COALESCE(uvt.total_upvotes,0)     AS total_upvotes,
        COALESCE(uvt.total_downvotes,0)   AS total_downvotes,
        COALESCE(uvt.total_netvotes,0)    AS total_netvotes,
        ura.last_active_dt,
        ucr.distinct_close_reason_cnt,
        ROW_NUMBER() OVER (ORDER BY ups.reputation DESC, ups.total_score DESC) AS rep_score_rank
    FROM user_post_stats ups
    LEFT JOIN user_badge_stats ubs   ON ubs.userid = ups.user_id
    LEFT JOIN user_vote_totals uvt  ON uvt.user_id = ups.user_id
    LEFT JOIN user_recent_activity ura ON ura.user_id = ups.user_id
    LEFT JOIN user_close_reason ucr ON ucr.user_id = ups.user_id
    GROUP BY
        ups.user_id, ups.displayname, ups.reputation, ups.question_cnt, ups.answer_cnt,
        ups.total_score, ups.last_post_dt, ubs.gold_badge_cnt, ubs.silver_badge_cnt, ubs.bronze_badge_cnt,
        uvt.total_upvotes, uvt.total_downvotes, uvt.total_netvotes, ura.last_active_dt, ucr.distinct_close_reason_cnt
)

SELECT
    uc.user_id,
    uc.displayname,
    uc.reputation,
    uc.question_cnt,
    uc.answer_cnt,
    uc.total_score,
    uc.gold_badge_cnt,
    uc.silver_badge_cnt,
    uc.bronze_badge_cnt,
    uc.total_upvotes,
    uc.total_downvotes,
    uc.total_netvotes,
    uc.last_active_dt,
    uc.distinct_close_reason_cnt,
    uc.rep_score_rank,
    CASE
        WHEN uc.rep_score_rank <= 10  THEN 'Top10'
        WHEN uc.rep_score_rank <= 100 THEN 'Top100'
        ELSE 'Other'
    END AS rank_category
FROM user_combined uc
WHERE uc.reputation IS NOT NULL
  AND (uc.question_cnt + uc.answer_cnt) > 0
  AND (uc.total_netvotes > 0 OR uc.gold_badge_cnt > 0)

UNION ALL

SELECT
    NULL AS user_id,
    'Tag Summary' AS displayname,
    NULL AS reputation,
    NULL AS question_cnt,
    NULL AS answer_cnt,
    SUM(ta.tag_total_score) AS total_score,
    NULL AS gold_badge_cnt,
    NULL AS silver_badge_cnt,
    NULL AS bronze_badge_cnt,
    NULL AS total_upvotes,
    NULL AS total_downvotes,
    NULL AS total_netvotes,
    MAX(ta.most_recent_post_dt) AS last_active_dt,
    NULL AS distinct_close_reason_cnt,
    NULL AS rep_score_rank,
    'TagAggregate' AS rank_category
FROM tag_aggregates ta
WHERE ta.tag_total_score IS NOT NULL

ORDER BY rep_score_rank NULLS LAST, total_score DESC;