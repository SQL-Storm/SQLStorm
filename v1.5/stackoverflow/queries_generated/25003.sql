-- {"query": "25003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2033} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                                   AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)           AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)           AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)           AS BronzeBadges,
        COALESCE(SUM(v.Score), 0)                              AS TotalPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)        AS RankByRep
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v    ON v.PostId = p.Id AND v.VoteTypeId = 2   -- up‑votes
    GROUP BY u.Id, u.DisplayName, u.Reputation
), 
TopUsers AS (
    SELECT *
    FROM UserStats
    WHERE RankByRep <= 100
), 
TagQuestionStats AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) FILTER (WHERE p.Score >= 5)                AS HighScoreQs,
        COUNT(*)                                            AS TotalQs,
        AVG(p.ViewCount)                                    AS AvgViews,
        MAX(p.CreationDate)                                 AS LatestQuestion
    FROM Posts p
    WHERE p.PostTypeId = 1   -- Question
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
), 
AnswerPerformance AS (
    SELECT 
        a.OwnerUserId,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END)      AS HighlyScoredAnswers,
        AVG(a.Score)                                        AS AvgAnswerScore,
        MAX(a.CreationDate)                                 AS LatestAnswer
    FROM Posts a
    WHERE a.PostTypeId = 2   -- Answer
    GROUP BY a.OwnerUserId
), 
DuplicateInfo AS (
    SELECT 
        pl.PostId        AS DuplicateOf,
        pl.RelatedPostId AS OriginalPost,
        ph.CreationDate  AS ClosedDate,
        ph.Comment       AS CloseReasonJson
    FROM PostLinks pl
    JOIN PostHistory ph ON ph.PostId = pl.PostId
    WHERE pl.LinkTypeId = 3               -- Duplicate link
      AND ph.PostHistoryTypeId = 10       -- Post Closed
), 
UserCombined AS (
    SELECT 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.BadgeCount,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.TotalPostScore,
        tq.Tag,
        tq.HighScoreQs,
        tq.TotalQs,
        tq.AvgViews,
        ap.HighlyScoredAnswers,
        ap.AvgAnswerScore,
        di.DuplicateOf,
        di.OriginalPost,
        CASE
            WHEN di.CloseReasonJson IS NULL THEN 'N/A'
            ELSE COALESCE(NULLIF(di.CloseReasonJson, ''), 'Unknown')
        END AS CloseReason
    FROM TopUsers tu
    LEFT JOIN TagQuestionStats tq ON tq.OwnerUserId = tu.Id
    LEFT JOIN AnswerPerformance ap ON ap.OwnerUserId = tu.Id
    LEFT JOIN DuplicateInfo di 
        ON di.DuplicateOf = ANY (
            SELECT Id 
            FROM Posts 
            WHERE OwnerUserId = tu.Id AND PostTypeId = 1
        )
)
SELECT *
FROM UserCombined
WHERE (BadgeCount > 5 OR GoldBadges > 0)
  AND (HighScoreQs > 0 OR HighlyScoredAnswers > 0)
  AND (CloseReason <> 'N/A')
ORDER BY Reputation DESC, BadgeCount DESC
LIMIT 200

UNION ALL

SELECT 
    NULL AS Id,
    'SUMMARY' AS DisplayName,
    NULL AS Reputation,
    NULL AS BadgeCount,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TotalPostScore,
    NULL AS Tag,
    NULL AS HighScoreQs,
    NULL AS TotalQs,
    NULL AS AvgViews,
    NULL AS HighlyScoredAnswers,
    NULL AS AvgAnswerScore,
    NULL AS DuplicateOf,
    NULL AS OriginalPost,
    NULL AS CloseReason
FROM (SELECT COUNT(*) AS TotalUsers FROM TopUsers) s;
