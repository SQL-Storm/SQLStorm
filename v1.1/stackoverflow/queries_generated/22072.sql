-- {"query": "22072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 610} 
WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') AS AssociatedTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    LEFT OUTER JOIN Posts tagp ON tagp.OwnerUserId = u.Id AND tagp.Tags IS NOT NULL
    LEFT OUTER JOIN Tags t ON t.TagName = ANY(string_to_array(substring(tagp.Tags, 2, length(tagp.Tags)-2), '><'))
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC, Reputation DESC) AS RankByBadges,
        DENSE_RANK() OVER (PARTITION BY BadgeCount / 10 ORDER BY TotalScore DESC) AS DenseRankScore
    FROM UserStats
    WHERE Reputation > 1000
      AND QuestionCount > 0
      AND (TotalScore > 10 OR BadgeCount > 5)
)
SELECT
    ru.*,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ru.UserId
    ) AND v.VoteTypeId IN (2,3)) AS TotalVotesReceived,
    CASE
        WHEN ru.AvgPostScore > 10 THEN 'High Scorer'
        WHEN ru.AvgPostScore BETWEEN 5 AND 10 THEN 'Medium Scorer'
        ELSE 'Low Scorer'
    END AS ScoreCategory,
    COALESCE((SELECT ph.Id FROM PostHistory ph WHERE ph.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ru.UserId
    ) AND ph.PostHistoryTypeId = 24 ORDER BY ph.CreationDate DESC LIMIT 1), -1) AS LastEditHistoryId
FROM RankedUsers ru
WHERE ru.RankByBadges <= 100
UNION
SELECT
    us.*,
    0 AS TotalVotesReceived,
    'No Rank' AS ScoreCategory,
    NULL AS LastEditHistoryId
FROM UserStats us
WHERE us.BadgeCount = 0
  AND us.QuestionCount > 0
ORDER BY RankByBadges ASC NULLS LAST, UserId DESC;