WITH
user_badge_counts AS (
    SELECT u.Id                                   AS user_id,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
           SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_badge_cnt
    FROM   Users u
    LEFT   JOIN Badges b ON b.UserId = u.Id
    GROUP  BY u.Id, u.DisplayName, u.Reputation
),
top_users AS (
    SELECT *
    FROM   user_badge_counts
    ORDER  BY Reputation DESC, gold_badges DESC, silver_badges DESC
    LIMIT  100
),
recent_questions AS (
    SELECT p.Id,
           p.Title,
           p.CreationDate,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.Tags,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                              ORDER BY p.CreationDate DESC) AS rn
    FROM   Posts p
    WHERE  p.PostTypeId = 1
),
user_recent_q AS (
    SELECT rq.*
    FROM   recent_questions rq
    JOIN   top_users tu ON tu.user_id = rq.OwnerUserId
    WHERE  rq.rn = 1
),
vote_aggregates AS (
    SELECT v.PostId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS up_votes,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS down_votes,
           MAX(v.CreationDate)                         AS last_vote_dt
    FROM   Votes v
    GROUP  BY v.PostId
),
comment_aggregates AS (
    SELECT c.PostId,
           COUNT(*)                                 AS comment_cnt,
           MAX(c.CreationDate)                      AS last_comment_dt
    FROM   Comments c
    GROUP  BY c.PostId
),
tag_stats AS (
    SELECT t.TagName,
           t.Count                                 AS tag_use_cnt,
           AVG(p.ViewCount)                        AS avg_views,
           COUNT(p.Id)                             AS q_count
    FROM   Tags t
    JOIN   Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE  p.PostTypeId = 1
    GROUP  BY t.TagName, t.Count
)
SELECT
    tu.user_id,
    tu.DisplayName,
    tu.Reputation,
    tu.gold_badges,
    tu.silver_badges,
    tu.bronze_badges,
    COALESCE(urq.Title, 'No recent question')                 AS recent_q_title,
    urq.CreationDate                                          AS recent_q_date,
    COALESCE(vu.up_votes, 0)                                  AS recent_q_upvotes,
    COALESCE(vu.down_votes, 0)                                AS recent_q_downvotes,
    COALESCE(ca.comment_cnt, 0)                               AS recent_q_comments,
    COALESCE(tl.avg_views, 0)                                 AS avg_views_all_q,
    COALESCE(tl.q_count, 0)                                   AS total_q_all_tags,
    CASE
        WHEN tu.Reputation > 20000 THEN 'Elite'
        WHEN tu.Reputation > 10000 THEN 'Pro'
        ELSE 'Member'
    END                                                       AS reputation_tier,
    STRING_AGG(DISTINCT tl.TagName, ', ') FILTER (WHERE tl.TagName IS NOT NULL)
                                                               AS top_5_tags
FROM top_users tu
LEFT JOIN user_recent_q urq ON urq.OwnerUserId = tu.user_id
LEFT JOIN vote_aggregates vu ON vu.PostId = urq.Id
LEFT JOIN comment_aggregates ca ON ca.PostId = urq.Id
LEFT JOIN LATERAL (
        SELECT ts.TagName, ts.avg_views, ts.q_count, ts.tag_use_cnt
        FROM   tag_stats ts
        ORDER  BY ts.tag_use_cnt DESC
        LIMIT  5
) tl ON TRUE
GROUP BY
    tu.user_id, tu.DisplayName, tu.Reputation,
    tu.gold_badges, tu.silver_badges, tu.bronze_badges,
    urq.Title, urq.CreationDate,
    vu.up_votes, vu.down_votes,
    ca.comment_cnt,
    tl.avg_views, tl.q_count, tl.TagName,
    tu.Reputation

UNION ALL

SELECT
    NULL AS user_id,
    'Aggregate Summary' AS DisplayName,
    NULL AS Reputation,
    NULL AS gold_badges,
    NULL AS silver_badges,
    NULL AS bronze_badges,
    NULL AS recent_q_title,
    NULL AS recent_q_date,
    SUM(vu.up_votes)                               AS total_upvotes,
    SUM(vu.down_votes)                             AS total_downvotes,
    SUM(ca.comment_cnt)                            AS total_comments,
    AVG(ts.avg_views)                              AS overall_avg_views,
    SUM(ts.q_count)                                AS overall_q_cnt,
    NULL AS reputation_tier,
    STRING_AGG(DISTINCT ts.TagName, ', ')          AS all_popular_tags
FROM   vote_aggregates vu
JOIN   comment_aggregates ca ON ca.PostId = vu.PostId
JOIN   Posts p               ON p.Id = vu.PostId
JOIN   tag_stats ts          ON p.Tags LIKE '%' || ts.TagName || '%'
WHERE  p.PostTypeId = 1;