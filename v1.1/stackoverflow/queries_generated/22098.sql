-- {"query": "22098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 924} 
WITH UserPostStats AS (
  SELECT u.Id AS UserId, u.Reputation, u.DisplayName,
         COUNT(DISTINCT p.Id) AS TotalPosts,
         SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScoreSum,
         AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
         COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate > p.CreationDate) AS RecentComments
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON p.Id = c.PostId
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
BadgeCounts AS (
  SELECT UserId,
         COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
         COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
         COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
VoteAggregates AS (
  SELECT v.UserId,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesOffered
  FROM Votes v
  GROUP BY v.UserId
)
SELECT ups.UserId, ups.Reputation, ups.DisplayName,
       COALESCE(ups.TotalPosts, 0) AS TotalPosts,
       CASE WHEN ups.QuestionScoreSum > 100 THEN 'High Scorer' 
            WHEN ups.QuestionScoreSum BETWEEN 10 AND 100 THEN 'Moderate' 
            ELSE 'Low' END AS ScoreCategory,
       ROUND(COALESCE(ups.AvgAnswerScore, 0), 2) AS AvgAnswerScore,
       COALESCE(bc.GoldBadges, 0) AS GoldBadges,
       COALESCE(bc.SilverBadges, 0) AS SilverBadges,
       COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(va.UpvotesReceived, 0) - COALESCE(va.DownvotesReceived, 0) AS NetVotes,
       COALESCE(va.TotalBountiesOffered, 0) AS TotalBounties,
       (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
        FROM Posts p 
        JOIN Tags t ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0 
        WHERE p.OwnerUserId = ups.UserId AND p.PostTypeId = 1) AS QuestionTags,
       ROW_NUMBER() OVER (ORDER BY ups.Reputation DESC) AS GlobalRank,
       LAG(ups.Reputation, 1) OVER (ORDER BY ups.Reputation DESC) - ups.Reputation AS RepGapToPrev,
       EXISTS (
         SELECT 1 FROM PostLinks pl 
         JOIN Posts p ON pl.PostId = p.Id 
         WHERE p.OwnerUserId = ups.UserId AND pl.LinkTypeId = 3
       ) AS HasDuplicates,
       (SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = ups.UserId AND c2.Text LIKE '%thanks%') AS ThankfulComments
FROM UserPostStats ups
LEFT JOIN BadgeCounts bc ON ups.UserId = bc.UserId
LEFT JOIN VoteAggregates va ON ups.UserId = va.UserId
WHERE ups.Reputation > 10
  AND (COALESCE(bc.GoldBadges, 0) > 0 OR COALESCE(ups.TotalPosts, 0) > 50)
UNION ALL
SELECT -1 AS UserId, NULL AS Reputation, 'Anonymous Users' AS DisplayName,
       COUNT(*) AS TotalPosts,
       NULL AS ScoreCategory,
       NULL AS AvgAnswerScore,
       NULL AS GoldBadges, NULL AS SilverBadges, NULL AS BronzeBadges,
       NULL AS NetVotes, NULL AS TotalBounties,
       NULL AS QuestionTags, NULL AS GlobalRank, NULL AS RepGapToPrev,
       NULL AS HasDuplicates, NULL AS ThankfulComments
FROM Posts p
WHERE p.OwnerUserId IS NULL OR p.OwnerUserId = -1
ORDER BY Reputation DESC NULLS LAST, NetVotes DESC;