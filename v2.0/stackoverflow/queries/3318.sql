WITH
user_posts AS (
    SELECT
        u.id                     AS user_id,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        COALESCE(SUM(p.score), 0)                 AS total_score,
        MAX(p.creationdate)                       AS last_post_dt
    FROM users u
    LEFT JOIN posts p
           ON p.owneruserid = u.id
    GROUP BY u.id
),
user_badges AS (
    SELECT
        b.userid                         AS user_id,
        COUNT(*)                         AS badge_total,
        COUNT(*) FILTER (WHERE b.class = 1) AS gold_cnt,
        COUNT(*) FILTER (WHERE b.class = 2) AS silver_cnt,
        COUNT(*) FILTER (WHERE b.class = 3) AS bronze_cnt,
        MAX(b.date)                      AS last_badge_dt,
        STRING_AGG(DISTINCT b.name, ', ') FILTER (WHERE b.class = 1) AS gold_names
    FROM badges b
    GROUP BY b.userid
),
user_tag_stats AS (
    SELECT
        u.id                              AS user_id,
        t.tagname,
        COUNT(*)                          AS tag_use_cnt,
        ROW_NUMBER() OVER (PARTITION BY u.id ORDER BY COUNT(*) DESC) AS tag_rank
    FROM users u
    JOIN posts p
         ON p.owneruserid = u.id
        AND p.posttypeid = 1
        AND p.tags IS NOT NULL
    JOIN LATERAL unnest(string_to_array(substr(p.tags, 2, length(p.tags) - 2), '><')) AS split(tag) ON true
    JOIN tags t
         ON t.tagname = split.tag
    GROUP BY u.id, t.tagname
),
top_users AS (
    SELECT
        u.id,
        u.displayname,
        u.reputation,
        COALESCE(up.question_cnt, 0)      AS questions,
        COALESCE(up.answer_cnt, 0)        AS answers,
        COALESCE(up.total_score, 0)       AS score_sum,
        COALESCE(ub.badge_total, 0)       AS badges,
        COALESCE(ub.gold_cnt, 0)          AS gold_badges,
        COALESCE(ub.silver_cnt, 0)        AS silver_badges,
        COALESCE(ub.bronze_cnt, 0)        AS bronze_badges,
        ub.last_badge_dt,
        up.last_post_dt,
        ROW_NUMBER() OVER (ORDER BY u.reputation DESC) AS rep_rank
    FROM users u
    LEFT JOIN user_posts up  ON up.user_id = u.id
    LEFT JOIN user_badges ub ON ub.user_id = u.id
    WHERE u.reputation > 10000
),
recent_close_votes AS (
    SELECT
        ph.postid,
        COUNT(*)                AS close_vote_cnt,
        MAX(ph.creationdate)    AS last_close_vote_dt
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 10
    GROUP BY ph.postid
),
final_user AS (
    SELECT
        tu.id,
        tu.displayname,
        tu.reputation,
        tu.rep_rank,
        tu.questions,
        tu.answers,
        tu.score_sum,
        tu.badges,
        tu.gold_badges,
        tu.silver_badges,
        tu.bronze_badges,
        tu.last_badge_dt,
        tu.last_post_dt,
        COALESCE(rcv.close_vote_cnt, 0)      AS recent_close_votes,
        rcv.last_close_vote_dt,
        CASE WHEN tu.badges = 0 THEN NULL
             ELSE CAST(tu.gold_badges AS double precision) / tu.badges END AS gold_badge_ratio,
        CASE
            WHEN tu.reputation IS NULL          THEN 'Unknown'
            WHEN tu.reputation >= 20000        THEN 'Legendary'
            WHEN tu.reputation >= 10000        THEN 'Expert'
            ELSE 'Active'
        END                                 AS reputation_tier
    FROM top_users tu
    LEFT JOIN LATERAL (
        SELECT rcv.*
        FROM recent_close_votes rcv
        WHERE rcv.postid = (
            SELECT p.id
            FROM posts p
            WHERE p.owneruserid = tu.id
            ORDER BY p.creationdate DESC
            LIMIT 1
        )
    ) rcv ON true
)
SELECT
    fu.id,
    fu.displayname,
    fu.reputation,
    fu.rep_rank,
    fu.questions,
    fu.answers,
    fu.score_sum,
    fu.badges,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.last_badge_dt,
    fu.last_post_dt,
    fu.recent_close_votes,
    fu.last_close_vote_dt,
    fu.gold_badge_ratio,
    fu.reputation_tier,
    uts.tagname,
    uts.tag_use_cnt
FROM final_user fu
LEFT JOIN LATERAL (
    SELECT
        uts.tagname,
        uts.tag_use_cnt
    FROM user_tag_stats uts
    WHERE uts.user_id = fu.id
      AND uts.tag_rank <= 3
    ORDER BY uts.tag_use_cnt DESC
    LIMIT 3
) uts ON true
ORDER BY fu.rep_rank
LIMIT 100;