-- {"query": "22081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 872} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(SUM(p.Score), 0) AS TotalPostScore,
           COUNT(p.Id) AS PostCount,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
           AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT u.Id,
           COUNT(b.Id) AS BadgeCount,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeCount,
           SUM(CASE WHEN b.Class = 1 THEN 100 WHEN b.Class = 2 THEN 10 WHEN b.Class = 3 THEN 1 ELSE 0 END) AS WeightedBadgeScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
VoteStats AS (
    SELECT u.Id,
           COUNT(v.Id) AS VoteCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id
)
SELECT us.Id,
       us.DisplayName,
       us.TotalPostScore,
       us.PostCount,
       us.QuestionCount,
       us.AnswerCount,
       us.AvgPostScore,
       bs.BadgeCount,
       bs.GoldCount,
       bs.SilverCount,
       bs.BronzeCount,
       bs.WeightedBadgeScore,
       vs.NetVotesReceived,
       COALESCE(us.TotalPostScore, 0) + COALESCE(us.Reputation * 0.1, 0) + COALESCE(bs.WeightedBadgeScore, 0) + COALESCE(vs.NetVotesReceived, 0) AS CompositeScore,
       ROW_NUMBER() OVER (ORDER BY (COALESCE(us.TotalPostScore, 0) + COALESCE(us.Reputation * 0.1, 0) + COALESCE(bs.WeightedBadgeScore, 0) + COALESCE(vs.NetVotesReceived, 0)) DESC) AS GlobalRank,
       RANK() OVER (PARTITION BY bs.GoldCount ORDER BY (COALESCE(us.TotalPostScore, 0) + COALESCE(us.Reputation * 0.1, 0) + COALESCE(bs.WeightedBadgeScore, 0) + COALESCE(vs.NetVotesReceived, 0)) DESC) AS RankWithinGoldGroup,
       CASE 
           WHEN us.PostCount > 0 THEN CONCAT(us.DisplayName, ' has ', CAST(us.PostCount AS VARCHAR), ' posts, avg score: ', CAST(ROUND(COALESCE(us.AvgPostScore, 0), 2) AS VARCHAR))
           ELSE CONCAT(us.DisplayName, ' has no posts')
       END AS UserInfo,
       (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = us.Id AND p2.Score > (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.OwnerUserId = us.Id)) AS HighScorePostCount,
       EXISTS (
           SELECT 1 FROM Badges b2 
           WHERE b2.UserId = us.Id AND b2.Name LIKE '%tag%' AND b2.TagBased = 1
       ) AS HasTagBasedBadge
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.Id = bs.Id
LEFT JOIN VoteStats vs ON us.Id = vs.Id
WHERE us.Reputation > 0
  AND (us.PostCount > 0 OR bs.BadgeCount > 0)
ORDER BY GlobalRank
LIMIT 100;
