-- {"query": "23019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1003} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 0) AS QuestionCount,
           COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2), 0) AS AnswerCount
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.CreationDate > '2010-01-01'
),
PostAnalytics AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.Tags,
           CASE WHEN p.AcceptedAnswerId IS NULL THEN 'Unaccepted' ELSE 'Accepted' END AS AcceptanceStatus,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
           NULLIF(p.FavoriteCount, 0) AS AdjustedFavorites,
           STRING_AGG(SPLIT_PART(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')), '>', 1), ', ') AS TagList
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId, p.OwnerUserId, p.CreationDate, p.FavoriteCount
),
BadgeSummary AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
CombinedPosts AS (
    SELECT pa.Id AS PostId, pa.Title, pa.Score, pa.ViewCount, pa.TagList,
           v.VoteTypeId, COUNT(v.Id) AS VoteCount
    FROM PostAnalytics pa
    INNER JOIN Votes v ON v.PostId = pa.Id
    GROUP BY pa.Id, pa.Title, pa.Score, pa.ViewCount, pa.TagList, v.VoteTypeId
    UNION
    SELECT pa.Id AS PostId, pa.Title, pa.Score, pa.ViewCount, pa.TagList,
           NULL AS VoteTypeId, 0 AS VoteCount
    FROM PostAnalytics pa
    WHERE NOT EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = pa.Id)
),
UserPostDetails AS (
    SELECT au.Id AS UserId, au.DisplayName, au.UserRank, au.QuestionCount, au.AnswerCount,
           cp.PostId, cp.Title, cp.Score, cp.ViewCount, cp.TagList,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cp.PostId AND c.Score > 0) AS PositiveComments,
           ph.PostHistoryTypeId,
           LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
           DATEDIFF('day', COALESCE(LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate), p.CreationDate), ph.CreationDate) AS DaysBetweenEdits
    FROM ActiveUsers au
    LEFT OUTER JOIN Posts p ON p.OwnerUserId = au.Id
    LEFT OUTER JOIN CombinedPosts cp ON cp.PostId = p.Id
    LEFT OUTER JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.Score > 10 OR p.ViewCount > 1000
      AND (ph.PostHistoryTypeId IN (4,5,6) OR ph.PostHistoryTypeId IS NULL)
)
SELECT upd.UserId, upd.DisplayName, upd.UserRank,
       bs.BadgeCount, bs.GoldBadges, bs.LatestBadgeDate,
       upd.PostId, upd.Title, upd.Score, upd.ViewCount, upd.TagList,
       upd.PositiveComments, upd.PostHistoryTypeId,
       CASE WHEN upd.DaysBetweenEdits > 30 THEN 'Infrequent Edits' ELSE 'Frequent Edits' END AS EditFrequency,
       (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = upd.UserId AND PostTypeId = 1) AS AvgQuestionScore,
       RANK() OVER (PARTITION BY upd.UserId ORDER BY upd.Score DESC) AS PostRankWithinUser
FROM UserPostDetails upd
LEFT OUTER JOIN BadgeSummary bs ON bs.UserId = upd.UserId
WHERE upd.QuestionCount + upd.AnswerCount > 5
  AND (upd.PreviousEditDate IS NULL OR upd.DaysBetweenEdits IS NOT NULL)
ORDER BY upd.UserRank, upd.PostRankWithinUser;
