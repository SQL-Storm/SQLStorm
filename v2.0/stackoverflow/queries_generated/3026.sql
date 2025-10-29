-- {"query": "3026.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2552} 

/*  Benchmark query – combines CTEs, window functions, outer joins, 
    correlated sub‑queries, set operators, string handling and NULL logic */
WITH
-- 1. Basic per‑user aggregates
usr AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views,0)                    AS total_views,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS net_votes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS gold_badges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS silver_badges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS bronze_badges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS q_count,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS a_count,
        (SELECT COUNT(*) FROM Votes v
            JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
            WHERE v.UserId = u.Id AND vt.Name = 'UpMod')  AS up_votes_given,
        (SELECT COUNT(*) FROM Votes v
            JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
            WHERE v.UserId = u.Id AND vt.Name = 'DownMod') AS down_votes_given
    FROM Users u
),

-- 2. Recent activity per user (last 5 posts, Q or A)
recent_posts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.FavoriteCount,0) AS favorite_count,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)                -- questions or answers
),

top_recent AS (
    SELECT *
    FROM recent_posts
    WHERE rn <= 5
),

-- 3. Tag usage extracted from the Posts.Tags CSV field
post_tags AS (
    SELECT
        rp.Id                     AS post_id,
        rp.OwnerUserId            AS owner_id,
        trim(both '<>' FROM t.tag) AS tag_name
    FROM top_recent rp
    CROSS JOIN LATERAL regexp_split_to_table(
        COALESCE(rp.Tags,''),           -- Tags like "<c#><sql>"
        '><' ) AS t(tag)
),

-- 4. Popular tags (arbitrarily those with Count > 1 000)
popular_tags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 1000
),

-- 5. Aggregate vote, link and close‑event data per post
post_meta AS (
    SELECT
        p.Id                                        AS post_id,
        COUNT(DISTINCT v.Id)                        AS votes_received,
        COUNT(DISTINCT pl.Id)                       AS duplicate_links,
        COUNT(DISTINCT ph.Id)                       AS close_events
    FROM Posts p
    LEFT JOIN Votes v
        ON v.PostId = p.Id
        AND v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')
    LEFT JOIN PostLinks pl
        ON pl.PostId = p.Id
        AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
    LEFT JOIN PostHistory ph
        ON ph.PostId = p.Id
        AND ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    WHERE p.Id IN (SELECT post_id FROM top_recent)
    GROUP BY p.Id
)

SELECT
    u.user_id,
    u.DisplayName,
    u.Reputation,
    u.total_views,
    u.net_votes,
    u.gold_badges,
    u.silver_badges,
    u.bronze_badges,
    u.q_count,
    u.a_count,
    u.up_votes_given,
    u.down_votes_given,

    /* recent‑post aggregates */
    COALESCE(SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.Score END),0) AS recent_q_score,
    COALESCE(SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.Score END),0) AS recent_a_score,
    COALESCE(SUM(rp.ViewCount),0)                                AS recent_views,
    COALESCE(SUM(rp.favorite_count),0)                           AS recent_favorites,

    /* tag list (only popular tags that the user touched in recent posts) */
    STRING_AGG(DISTINCT pt.tag_name, ', ') FILTER (WHERE pt.tag_name IN (SELECT TagName FROM popular_tags))
        AS recent_popular_tags,

    /* post‑level meta aggregates */
    COALESCE(SUM(pm.votes_received),0)      AS recent_votes_received,
    COALESCE(SUM(pm.duplicate_links),0)    AS recent_duplicate_links,
    COALESCE(SUM(pm.close_events),0)       AS recent_close_events

FROM usr u
LEFT JOIN top_recent rp
    ON rp.OwnerUserId = u.user_id
LEFT JOIN post_tags pt
    ON pt.post_id = rp.Id
LEFT JOIN post_meta pm
    ON pm.post_id = rp.Id
WHERE u.Reputation > 1000                         -- filter to make the plan non‑trivial
GROUP BY
    u.user_id, u.DisplayName, u.Reputation, u.total_views, u.net_votes,
    u.gold_badges, u.silver_badges, u.bronze_badges,
    u.q_count, u.a_count, u.up_votes_given, u.down_votes_given
HAVING COUNT(rp.Id) > 0
ORDER BY u.Reputation DESC
LIMIT 100

UNION ALL

/* Dummy branch to exercise a set operator */
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,null,null,null,null,null,null,null
WHERE FALSE;
