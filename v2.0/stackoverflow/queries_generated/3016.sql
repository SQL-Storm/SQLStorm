-- {"query": "3016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1957} 

/* Complex benchmark query using CTEs, window functions, outer joins, correlated subqueries,
   set operators, string manipulation, and NULL logic */
WITH
    -- 1. Extract individual tags from question posts
    tag_extraction AS (
        SELECT
            p.Id           AS PostId,
            unnest(string_to_array(
                substring(p.Tags FROM 2 FOR length(p.Tags)-2),
                '><'
            ))               AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1               -- only questions
          AND p.Tags IS NOT NULL
    ),

    -- 2. Count tag usage per user
    user_tag_counts AS (
        SELECT
            p.OwnerUserId                 AS UserId,
            te.Tag,
            COUNT(*)                      AS TagUseCount
        FROM Posts p
        JOIN tag_extraction te ON te.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, te.Tag
    ),

    -- 3. Rank tags per user, keep top 3
    ranked_user_tags AS (
        SELECT
            utc.*,
            ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY utc.TagUseCount DESC) AS rn
        FROM user_tag_counts utc
    ),

    -- 4. Aggregate badge info per user
    user_badges AS (
        SELECT
            u.Id                                    AS UserId,
            MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS HasGoldBadge,
            COUNT(b.Id)                            AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),

    -- 5. Recent activity (last 30 days) per user
    recent_activity AS (
        SELECT
            p.OwnerUserId                 AS UserId,
            MAX(p.LastActivityDate)       AS LastActivity
        FROM Posts p
        WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
        GROUP BY p.OwnerUserId
    ),

    -- 6. Vote aggregates per user (correlated subquery style)
    vote_aggregates AS (
        SELECT
            p.OwnerUserId                 AS UserId,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVoteCount,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVoteCount
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    -- 7. Core post statistics per user
    post_stats AS (
        SELECT
            p.OwnerUserId                 AS UserId,
            COUNT(*)                      AS TotalPosts,
            AVG(p.Score)                  AS AvgScore,
            SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViews,
            MAX(p.CreationDate)           AS FirstPostDate,
            MIN(p.CreationDate)           AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- 8. Assemble final per‑user row set
    user_summary AS (
        SELECT
            u.Id                                 AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(ps.TotalPosts,0)            AS TotalPosts,
            COALESCE(ps.AvgScore,0)              AS AvgScore,
            COALESCE(ps.TotalViews,0)            AS TotalViews,
            ub.HasGoldBadge,
            ub.TotalBadges,
            ra.LastActivity,
            va.UpVoteCount,
            va.DownVoteCount,
            STRING_AGG(rt.Tag, ', ') FILTER (WHERE rt.rn <= 3) AS Top3Tags
        FROM Users u
        LEFT JOIN post_stats ps         ON ps.UserId = u.Id
        LEFT JOIN user_badges ub        ON ub.UserId = u.Id
        LEFT JOIN recent_activity ra    ON ra.UserId = u.Id
        LEFT JOIN vote_aggregates va    ON va.UserId = u.Id
        LEFT JOIN ranked_user_tags rt   ON rt.UserId = u.Id
        GROUP BY
            u.Id, u.DisplayName, u.Reputation,
            ps.TotalPosts, ps.AvgScore, ps.TotalViews,
            ub.HasGoldBadge, ub.TotalBadges,
            ra.LastActivity, va.UpVoteCount, va.DownVoteCount
    )

-- 9. Benchmark set operators: high‑rep active users UNION with mid‑rep prolific posters
SELECT *
FROM user_summary us
WHERE (us.TotalPosts > 100 AND us.Reputation > 10000)
   OR (us.LastActivity IS NOT NULL AND us.LastActivity > NOW() - INTERVAL '1 year')
ORDER BY us.Reputation DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT *
FROM user_summary us
WHERE us.Reputation BETWEEN 5000 AND 10000
  AND us.AvgScore IS NOT NULL
ORDER BY us.AvgScore DESC NULLS LAST
OFFSET 50 ROWS FETCH NEXT 50 ROWS ONLY;
