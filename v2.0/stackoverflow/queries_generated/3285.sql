-- {"query": "3285.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1451} 

WITH
    -- Users with their total badge counts and break‑down by class
    user_badges AS (
        SELECT
            b.UserId,
            COUNT(*)                                      AS total_badges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)  AS gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)  AS silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)  AS bronze
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Latest post (question or answer) per user and its score delta compared to previous post
    user_latest_posts AS (
        SELECT
            p.OwnerUserId                                   AS UserId,
            p.Id                                            AS PostId,
            p.PostTypeId,
            p.Score,
            p.CreationDate,
            LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
            p.Score - COALESCE(LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate),0) AS ScoreDelta,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ),

    -- Tag extraction and popularity weighting
    tag_stats AS (
        SELECT
            t.TagName,
            t.Count,
            SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS body_edits,
            SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS title_edits
        FROM Tags t
        LEFT JOIN PostHistory ph
            ON ph.PostId = t.ExcerptPostId OR ph.PostId = t.WikiPostId
        GROUP BY t.TagName, t.Count
    ),

    -- Aggregate voting info per post, using a correlated subquery for recent votes
    post_votes AS (
        SELECT
            p.Id                                              AS PostId,
            p.PostTypeId,
            p.Score,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvotes,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvotes,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5 AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') AS recent_favorites
        FROM Posts p
        WHERE p.PostTypeId IN (1,2)   -- questions or answers
    ),

    -- Users who have earned at least one gold badge and posted in the last year
    active_gold_users AS (
        SELECT
            u.Id                                             AS UserId,
            u.DisplayName,
            u.Reputation,
            ub.gold,
            ub.silver,
            ub.bronze,
            ub.total_badges,
            ulp.PostId,
            ulp.Score,
            ulp.ScoreDelta,
            pv.upvotes,
            pv.downvotes,
            pv.recent_favorites,
            COALESCE(string_agg(DISTINCT tg.TagName, ', '), '') AS recent_tags
        FROM Users u
        INNER JOIN user_badges ub          ON ub.UserId = u.Id
        LEFT JOIN (
            SELECT * FROM user_latest_posts WHERE rn = 1
        ) ulp                               ON ulp.UserId = u.Id
        LEFT JOIN post_votes pv            ON pv.PostId = ulp.PostId
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(p.Tags, '><')) AS TagName
            FROM Posts p
            WHERE p.Id = ulp.PostId AND p.Tags IS NOT NULL
        ) tg                               ON TRUE
        WHERE ub.gold > 0
          AND u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '5 years'
          AND (ulp.CreationDate IS NULL OR ulp.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year')
        GROUP BY
            u.Id, u.DisplayName, u.Reputation,
            ub.gold, ub.silver, ub.bronze, ub.total_badges,
            ulp.PostId, ulp.Score, ulp.ScoreDelta,
            pv.upvotes, pv.downvotes, pv.recent_favorites
    )

SELECT
    ag.UserId,
    ag.DisplayName,
    ag.Reputation,
    ag.total_badges,
    ag.gold,
    ag.silver,
    ag.bronze,
    ag.Score        AS latest_post_score,
    ag.ScoreDelta   AS latest_post_score_delta,
    ag.upvotes      AS latest_post_upvotes,
    ag.downvotes    AS latest_post_downvotes,
    ag.recent_favorites,
    ag.recent_tags,
    CASE
        WHEN ag.ScoreDelta > 0 AND ag.upvotes > ag.downvotes THEN 'RisingStar'
        WHEN ag.ScoreDelta < 0 AND ag.downvotes > ag.upvotes THEN 'FallingStar'
        ELSE 'Stable'
    END AS performance_flag,
    ROW_NUMBER() OVER (ORDER BY ag.Reputation DESC, ag.gold DESC, ag.silver DESC) AS rank_by_reputation
FROM active_gold_users ag
UNION ALL
SELECT
    NULL AS UserId,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS total_badges,
    NULL AS gold,
    NULL AS silver,
    NULL AS bronze,
    NULL AS latest_post_score,
    NULL AS latest_post_score_delta,
    NULL AS latest_post_upvotes,
    NULL AS latest_post_downvotes,
    NULL AS recent_favorites,
    NULL AS recent_tags,
    NULL AS performance_flag,
    NULL AS rank_by_reputation
FROM (SELECT 1) dummy
ORDER BY rank_by_reputation NULLS LAST;
