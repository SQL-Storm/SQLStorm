-- {"query": "28003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1487} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, p.Score
),
PostAnalytics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastEditDate,
        v.TotalVotes,
        ph.LastCloseReason,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        (SELECT MAX(CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = p.Id) AS LastEditActivity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS TotalVotes,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS VoteBalance
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            MAX(CASE WHEN PostHistoryTypeId = 10 THEN Comment END) AS LastCloseReason
        FROM PostHistory
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1,2)
      AND p.ClosedDate IS NULL
      AND array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) > 2
)
SELECT 
    ua.*,
    pa.PostId,
    pa.Title,
    pa.UserPostRank,
    pa.VoteBalance,
    pa.LastCloseReason,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pa.PostId AND p2.Score > 5) AS HighScoreAnswers,
    COALESCE(lt.Name, 'No Link') AS LinkType,
    CASE 
        WHEN ua.Reputation > 100000 THEN 'Legendary' 
        WHEN ua.Reputation > 50000 THEN 'Epic' 
        WHEN ua.Reputation > 10000 THEN 'Advanced' 
        ELSE 'Basic' 
    END AS UserTier
FROM UserActivity ua
JOIN PostAnalytics pa ON ua.UserId = pa.OwnerUserId
LEFT JOIN PostLinks pl ON pa.PostId = pl.PostId AND pl.LinkTypeId = 3
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE ua.GoldBadges > 0
  AND pa.LastEditActivity > '2020-01-01'
  AND pa.VoteBalance > (SELECT AVG(VoteBalance) FROM PostAnalytics)
  AND EXISTS (SELECT 1 FROM Comments c2 WHERE c2.PostId = pa.PostId AND LENGTH(c2.Text) > 100)
HAVING COUNT(pa.PostId) OVER (PARTITION BY ua.UserId) > 5
ORDER BY ua.Reputation DESC, pa.VoteBalance DESC
LIMIT 100;
