-- {"query": "3445.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2425} 

WITH
    -- User level aggregates, including badge counts and post counts
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
        FROM Users u
        WHERE u.Reputation > 1000
    ),

    -- Tag popularity with optional excerpt/wiki length calculations
    TagPopularity AS (
        SELECT
            t.TagName,
            t.Count                                     AS TagUseCount,
            COALESCE(LENGTH(e.Body),0)                  AS ExcerptLength,
            COALESCE(LENGTH(w.Body),0)                  AS WikiLength
        FROM Tags t
        LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
        LEFT JOIN Posts w ON w.Id = t.WikiPostId
        WHERE t.IsModeratorOnly = 0
    ),

    -- Detailed per‑question metrics, using window functions and correlated subqueries
    PostMetrics AS (
        SELECT
            p.Id,
            p.Title,
            p.PostTypeId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            COALESCE(p.AnswerCount,0)                  AS AnswerCount,
            COALESCE(p.FavoriteCount,0)                AS FavoriteCount,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC)   AS RankByScore,
            CASE
                WHEN p.ViewCount IS NULL OR p.ViewCount = 0 THEN NULL
                ELSE CAST(p.Score AS float) / p.ViewCount
            END                                         AS ScorePerView
        FROM Posts p
        WHERE p.PostTypeId = 1                 -- only questions
    ),

    -- Aggregated close‑reason counts per question
    CloseReasonAgg AS (
        SELECT
            ph.PostId,
            COUNT(*) FILTER (WHERE TRY_CAST(ph.Comment AS int) = 101) AS DuplicateCount,
            COUNT(*) FILTER (WHERE TRY_CAST(ph.Comment AS int) = 102) AS OffTopicCount,
            COUNT(*) FILTER (WHERE TRY_CAST(ph.Comment AS int) = 103) AS NeedsDetailsCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10                         -- Post Closed
        GROUP BY ph.PostId
    ),

    -- Rank questions globally by score‑per‑view while pulling in close‑reason and owner data
    TopPosts AS (
        SELECT
            pm.Id,
            pm.Title,
            pm.Score,
            pm.ViewCount,
            pm.RankByScore,
            COALESCE(cr.DuplicateCount,0)          AS DuplicateVotes,
            COALESCE(cr.OffTopicCount,0)           AS OffTopicVotes,
            COALESCE(cr.NeedsDetailsCount,0)       AS NeedsDetailsVotes,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (
                ORDER BY (pm.Score::float) / NULLIF(pm.ViewCount,0) DESC
            )                                      AS GlobalScorePerViewRank,
            pm.ScorePerView
        FROM PostMetrics pm
        LEFT JOIN CloseReasonAgg cr ON cr.PostId = pm.Id
        LEFT JOIN Users u          ON u.Id = pm.OwnerUserId
        WHERE pm.Score > 10
    ),

    -- Combine user stats with top posts, compute a composite badge score, and format nullable values
    FinalResult AS (
        SELECT
            tp.Id,
            tp.Title,
            tp.Score,
            tp.ViewCount,
            tp.GlobalScorePerViewRank,
            tp.DuplicateVotes,
            tp.OffTopicVotes,
            tp.NeedsDetailsVotes,
            tp.DisplayName,
            tp.Reputation,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            us.QuestionCount,
            us.AnswerCount,
            (us.GoldBadges*100 + us.SilverBadges*10 + us.BronzeBadges) AS BadgeScore,
            CASE
                WHEN tp.ScorePerView IS NULL THEN 'N/A'
                ELSE ROUND(tp.ScorePerView,4)::text
            END                                                     AS ScorePerViewStr
        FROM TopPosts tp
        JOIN UserStats us ON us.Id = tp.OwnerUserId
        WHERE tp.GlobalScorePerViewRank <= 100
    )

SELECT *
FROM FinalResult

UNION ALL
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE EXISTS (SELECT 1 FROM (SELECT 1) AS dummy WHERE FALSE)   -- forces a UNION ALL branch with no rows

ORDER BY GlobalScorePerViewRank NULLS LAST
LIMIT 150;
