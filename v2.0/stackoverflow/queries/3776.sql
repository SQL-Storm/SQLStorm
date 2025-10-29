-- {"query": "3776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1942}
WITH q_posts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.Title,
        p.FavoriteCount,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tagged AS (
    SELECT 
        q.Id        AS QuestionId,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM q.Tags), '><')) AS Tag
    FROM q_posts q
),
user_stats AS (
    SELECT 
        u.Id                                      AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT q.Id)                      AS TotalQuestions,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) AS RecentAnswers,
        COALESCE(SUM(q.Score),0)                  AS TotalQuestionScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(SUM(q.Score),0) DESC) AS RepScoreRank
    FROM Users u
    LEFT JOIN q_posts q   ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a    ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_counts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
latest_close AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
dup_counts AS (
    SELECT 
        pl.PostId,
        COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalQuestionScore,
    us.RepScoreRank,
    COALESCE(bc.GoldBadges,0)   AS GoldBadges,
    COALESCE(bc.SilverBadges,0) AS SilverBadges,
    COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
    CASE 
        WHEN lc.LastCloseDate IS NOT NULL 
             AND (lc.LastReopenDate IS NULL OR lc.LastCloseDate > lc.LastReopenDate) 
        THEN 1 ELSE 0 
    END                         AS IsCurrentlyClosed,
    STRING_AGG(DISTINCT tg.Tag, ', ') FILTER (WHERE tg.Tag IS NOT NULL) AS TopTags,
    COALESCE(dc.DuplicateCount,0) AS DuplicateCount
FROM user_stats us
LEFT JOIN badge_counts   bc ON bc.UserId = us.UserId
LEFT JOIN q_posts         q  ON q.OwnerUserId = us.UserId
LEFT JOIN tagged          tg ON tg.QuestionId = q.Id
LEFT JOIN latest_close    lc ON lc.PostId = q.Id
LEFT JOIN dup_counts      dc ON dc.PostId = q.Id
WHERE us.Reputation > 10000
GROUP BY 
    us.UserId, us.DisplayName, us.Reputation, us.TotalQuestionScore,
    us.RepScoreRank, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
    lc.LastCloseDate, lc.LastReopenDate, dc.DuplicateCount

UNION ALL

SELECT 
    NULL AS UserId,
    'No High-Reputation Users' AS DisplayName,
    0 AS Reputation,
    0 AS TotalQuestionScore,
    NULL AS RepScoreRank,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS IsCurrentlyClosed,
    NULL AS TopTags,
    0 AS DuplicateCount
WHERE NOT EXISTS (SELECT 1 FROM user_stats WHERE Reputation > 10000)

ORDER BY Reputation DESC NULLS LAST, UserId
LIMIT 100;