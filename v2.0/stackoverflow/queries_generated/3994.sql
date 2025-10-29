-- {"query": "3994.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2207} 

WITH
-- Aggregate post counts per user
post_agg AS (
    SELECT
        p.OwnerUserId            AS user_id,
        COUNT(*)                 AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS total_answers,
        MAX(p.CreationDate)      AS latest_post_date
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- Aggregate comment counts per user
comment_agg AS (
    SELECT
        c.UserId                 AS user_id,
        COUNT(*)                 AS total_comments
    FROM Comments c
    GROUP BY c.UserId
),

-- Aggregate badge counts per user (by class)
badge_agg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),

-- Aggregate vote totals per post (used later in a correlated sub‑query)
vote_agg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),

-- Tag usage per user (tags are stored as “<tag1><tag2>”)
tag_agg AS (
    SELECT
        p.OwnerUserId                AS user_id,
        COUNT(DISTINCT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><'))) AS distinct_tags
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- Main user statistics with window ranking
user_stats AS (
    SELECT
        u.Id                                           AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(pa.total_posts, 0)                    AS post_count,
        COALESCE(pa.total_answers, 0)                  AS answer_count,
        COALESCE(ca.total_comments, 0)                 AS comment_count,
        COALESCE(ba.gold_badges, 0)                    AS gold_badges,
        COALESCE(ba.silver_badges, 0)                  AS silver_badges,
        COALESCE(ba.bronze_badges, 0)                  AS bronze_badges,
        COALESCE(ta.distinct_tags, 0)                  AS tag_variety,
        COALESCE(
            (SELECT SUM(vu.up_votes - vu.down_votes)
             FROM vote_agg vu
             WHERE vu.PostId = (
                 SELECT MIN(p2.Id)
                 FROM Posts p2
                 WHERE p2.OwnerUserId = u.Id
             )
            ), 0)                                      AS net_vote_score,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(pa.total_posts,0) DESC) AS rep_rank,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 5000  THEN 'Contributor'
            ELSE 'Novice'
        END                                            AS reputation_tier,
        pa.latest_post_date
    FROM Users u
    LEFT JOIN post_agg   pa ON pa.user_id   = u.Id
    LEFT JOIN comment_agg ca ON ca.user_id = u.Id
    LEFT JOIN badge_agg   ba ON ba.UserId   = u.Id
    LEFT JOIN tag_agg     ta ON ta.user_id = u.Id
)

SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.post_count,
    us.answer_count,
    us.comment_count,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.tag_variety,
    us.net_vote_score,
    us.rep_rank,
    us.reputation_tier,
    us.latest_post_date,
    /* Correlated sub‑query: how many close‑vote events this user has cast */
    (SELECT COUNT(*)
     FROM PostHistory ph
     WHERE ph.UserId = us.user_id
       AND ph.PostHistoryTypeId = 10)                AS close_votes_cast
FROM user_stats us
WHERE us.rep_rank <= 100
ORDER BY us.rep_rank
OFFSET 0 ROW FETCH NEXT 50 ROWS ONLY

UNION ALL

/* A single “summary” row to force a set‑operator path and add a tiny overhead */
SELECT
    NULL AS user_id,
    '--- SUMMARY ---' AS DisplayName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
LIMIT 1;
