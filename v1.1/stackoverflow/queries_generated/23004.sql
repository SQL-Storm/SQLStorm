-- {"query": "23004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 820} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 1000
),
PostDetails AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 'Upvote' ELSE NULL END, ', ') AS VoteTypes,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND (p.Tags LIKE '%sql%' OR p.Tags IS NULL)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId
),
BadgeSummary AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LatestGoldBadge
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
CombinedData AS (
    SELECT tu.Id AS UserId, tu.DisplayName, tu.Reputation, tu.UserRank, tu.AvgQuestionScore,
           pd.Id AS PostId, pd.Title, pd.Score, pd.ViewCount, pd.PositiveComments, pd.VoteTypes, pd.PostRank,
           bs.BadgeCount, bs.LatestGoldBadge,
           COALESCE(NULLIF(pd.Title, ''), 'Untitled') AS CleanTitle,
           (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pd.Id AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > '2020-01-01') AS EditCount
    FROM TopUsers tu
    FULL OUTER JOIN PostDetails pd ON tu.Id = pd.OwnerUserId
    LEFT JOIN BadgeSummary bs ON tu.Id = bs.UserId
    WHERE tu.UserRank <= 100 OR pd.PostRank = 1
    UNION
    SELECT u.Id, u.DisplayName, u.Reputation, 0 AS UserRank, 0 AS AvgQuestionScore,
           NULL AS PostId, NULL AS Title, 0 AS Score, 0 AS ViewCount, 0 AS PositiveComments, '' AS VoteTypes, 0 AS PostRank,
           COUNT(b.Id) AS BadgeCount, MAX(b.Date) AS LatestGoldBadge,
           '' AS CleanTitle, 0 AS EditCount
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation < 100 AND b.Class = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT UserId, DisplayName, Reputation, UserRank, AvgQuestionScore,
       PostId, CleanTitle, Score, ViewCount, PositiveComments, VoteTypes, PostRank,
       BadgeCount, LatestGoldBadge, EditCount,
       CASE WHEN LatestGoldBadge IS NULL THEN 'No Gold Badges' ELSE TO_CHAR(LatestGoldBadge, 'YYYY-MM-DD') END AS GoldBadgeStatus,
       SUM(Score) OVER (PARTITION BY UserId ORDER BY PostRank) AS CumulativeScore
FROM CombinedData
WHERE (Reputation > 5000 OR BadgeCount > 10) AND (EditCount > 0 OR PostId IS NULL)
ORDER BY UserRank ASC, PostRank ASC;
