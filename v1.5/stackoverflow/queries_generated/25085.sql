-- {"query": "25085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2268} 

WITH
    RecentPosts AS (
        SELECT
            p.Id,
            p.OwnerUserId,
            p.PostTypeId,
            p.Score,
            p.Title,
            p.Tags,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
    ),
    UserBadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_cnt,
            MAX(b.Date) AS last_badge_date
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserVoteAgg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes,
            MAX(v.CreationDate) AS last_vote_date
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE vt.Id IN (2,3)
        GROUP BY v.PostId
    ),
    TagPostCounts AS (
        SELECT
            t.TagName,
            COUNT(p.Id) AS post_cnt,
            SUM(p.Score) AS total_score,
            MAX(p.CreationDate) AS latest_post_date
        FROM Tags t
        JOIN LATERAL (
            SELECT *
            FROM Posts p
            WHERE p.PostTypeId = 1
              AND p.Tags IS NOT NULL
              AND ('<' || REPLACE(p.Tags, '><', '> <') || '>') LIKE '%' || '<' || t.TagName || '>' || '%'
        ) p ON true
        GROUP BY t.TagName
    )
SELECT
    u.Id                                                AS user_id,
    COALESCE(u.DisplayName, u.EmailHash)                AS display_name,
    u.Reputation,
    ub.gold_cnt,
    ub.silver_cnt,
    ub.bronze_cnt,
    COALESCE(rp.Title, 'No recent post')                AS recent_title,
    rp.CreationDate                                     AS recent_post_date,
    COALESCE(uv.up_votes,0) - COALESCE(uv.down_votes,0) AS net_votes_on_recent,
    COALESCE(ub.last_badge_date, TIMESTAMP '1970-01-01') AS last_badge,
    tc.TagName,
    tc.post_cnt,
    tc.total_score,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY tc.total_score DESC) AS tag_rank,
    CASE
        WHEN u.Reputation > 20000                 THEN 'Legendary'
        WHEN u.Reputation BETWEEN 5000 AND 20000   THEN 'PowerUser'
        WHEN u.Reputation BETWEEN 1000 AND 4999    THEN 'Experienced'
        ELSE 'Newcomer'
    END                                           AS reputation_bucket,
    (COALESCE(ub.gold_cnt,0)   * 100
   + COALESCE(ub.silver_cnt,0) * 10
   + COALESCE(ub.bronze_cnt,0))
   + COALESCE(rp.Score,0) * 2
   + (COALESCE(uv.up_votes,0) - COALESCE(uv.down_votes,0)) AS engagement_score
FROM Users u
LEFT JOIN UserBadgeAgg ub ON ub.UserId = u.Id
LEFT JOIN (
    SELECT *
    FROM RecentPosts
    WHERE rn = 1
) rp ON rp.OwnerUserId = u.Id
LEFT JOIN UserVoteAgg uv ON uv.PostId = rp.Id
LEFT JOIN TagPostCounts tc ON tc.TagName = (
    SELECT split_part(tag, '>', 1)
    FROM unnest(string_to_array(rp.Tags, '><')) AS tag
    ORDER BY random()
    LIMIT 1
)
WHERE (u.CreationDate < NOW() - INTERVAL '1 year' OR u.Id IS NULL)

UNION ALL

SELECT
    NULL          AS user_id,
    'Aggregated Tag Summary' AS display_name,
    NULL          AS Reputation,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    t.TagName,
    t.post_cnt,
    t.total_score,
    NULL,
    NULL,
    NULL,
    NULL
FROM TagPostCounts t
ORDER BY engagement_score DESC NULLS LAST, user_id;
