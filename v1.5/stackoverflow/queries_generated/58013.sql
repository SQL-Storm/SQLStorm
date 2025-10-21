-- {"query": "58013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1151} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01' AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50
), CommentStats AS (
    SELECT PostId, COUNT(*) AS CommentCount, AVG(Score) AS AvgCommentScore
    FROM Comments
    WHERE CreationDate >= '2020-01-01'
    GROUP BY PostId
), VoteAggregates AS (
    SELECT PostId, 
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
           COUNT(*) AS TotalVotes
    FROM Votes
    WHERE CreationDate >= '2020-01-01'
    GROUP BY PostId
), BadgeSummary AS (
    SELECT UserId, 
           STRING_AGG(Name, ', ') AS BadgeNames,
           COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    WHERE Date >= '2020-01-01' AND TagBased = FALSE
    GROUP BY UserId
)
SELECT au.DisplayName, au.Reputation, au.PostCount,
       p.Title, p.Score, p.ViewCount, p.Tags,
       cs.CommentCount, cs.AvgCommentScore,
       va.Upvotes, va.Favorites, va.TotalVotes,
       bs.BadgeNames, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
       RANK() OVER (ORDER BY au.Reputation DESC) AS ReputationRank,
       DENSE_RANK() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagScoreRank
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN CommentStats cs ON p.Id = cs.PostId
LEFT JOIN VoteAggregates va ON p.Id = va.PostId
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
WHERE p.AcceptedAnswerId IS NOT NULL
  AND p.ClosedDate IS NULL
  AND EXISTS (
    SELECT 1 FROM PostHistory ph
    WHERE ph.PostId = p.Id
      AND ph.PostHistoryTypeId IN (2,5,6)
      AND ph.CreationDate >= '2020-01-01'
  )
ORDER BY au.Reputation DESC, p.Score DESC, va.TotalVotes DESC
LIMIT 1000;
