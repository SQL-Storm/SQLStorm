-- {"query": "58066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1610} 

WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation, CreationDate
    FROM Users
    WHERE Reputation > 10000
), UserBadges AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
), PostStats AS (
    SELECT OwnerUserId,
           COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS Questions,
           COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS Answers,
           AVG(Score) AS AvgPostScore,
           SUM(ViewCount) AS TotalViews,
           MAX(LastActivityDate) AS LastActivity
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
), VoteAggregates AS (
    SELECT v.UserId,
           COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS Upvotes,
           COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS Downvotes,
           COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS Bookmarks
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate > '2023-01-01'
    GROUP BY v.UserId
), EditHistory AS (
    SELECT UserId,
           COUNT(DISTINCT ph.Id) AS Edits,
           COUNT(DISTINCT CASE WHEN pht.Name = 'Post Closed' THEN ph.Id END) AS Closures
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.CreationDate BETWEEN '2020-01-01' AND '2024-01-01'
    GROUP BY UserId
)
SELECT hru.Id,
       hru.DisplayName,
       hru.Reputation,
       ub.GoldBadges,
       ub.SilverBadges,
       ub.BronzeBadges,
       ps.Questions,
       ps.Answers,
       ps.AvgPostScore,
       ps.TotalViews,
       va.Upvotes,
       va.Downvotes,
       va.Bookmarks,
       eh.Edits,
       eh.Closures,
       DENSE_RANK() OVER (ORDER BY hru.Reputation DESC) AS GlobalRank,
       ROW_NUMBER() OVER (PARTITION BY CASE WHEN ub.GoldBadges > 10 THEN 'Elite' ELSE 'Active' END ORDER BY ps.TotalViews DESC) AS ActivityRank
FROM HighRepUsers hru
LEFT JOIN UserBadges ub ON hru.Id = ub.UserId
LEFT JOIN PostStats ps ON hru.Id = ps.OwnerUserId
LEFT JOIN VoteAggregates va ON hru.Id = va.UserId
LEFT JOIN EditHistory eh ON hru.Id = eh.UserId
WHERE ps.Questions + ps.Answers > 100
  AND (va.Upvotes - va.Downvotes) > 500
  AND eh.Edits > 50
ORDER BY hru.Reputation DESC, ps.TotalViews DESC, va.Upvotes DESC
LIMIT 1000;
