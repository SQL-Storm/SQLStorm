-- {"query": "22061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 957} 
WITH RankedAnswers AS (
  SELECT p.Id AS AnswerId,
         p.ParentId AS QuestionId,
         p.Score,
         p.Body,
         ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank,
         CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END * 2 + LENGTH(COALESCE(p.Body, '')) / 1000.0 AS ComplexScore
  FROM Posts p
  WHERE p.PostTypeId = 2
),
AnswererSummaries AS (
  SELECT a.AnswerId,
         a.QuestionId,
         a.Score,
         a.ComplexScore,
         q.OwnerUserId AS QuestionerId,
         a.PostId AS AnswerId,  -- wait, AnswerId is p.Id
         u.Id AS AnswererId,
         u.Reputation,
         COALESCE(a.Score, 0) + u.Reputation / 1000.0 AS AdjustedScore
  FROM RankedAnswers a
  JOIN Posts q ON a.QuestionId = q.Id
  LEFT JOIN Users u ON a.AnswerId = u.Id  -- wait, no, Post owner
  INNER JOIN Users u ON (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = a.AnswerId) = u.Id
  WHERE a.Rank = 1
),
QuestionSummaries AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.OwnerUserId,
         q.Tags,
         COALESCE(ra.Score, 0) AS TopAnswerScore,
         COALESCE(ra.ComplexScore, 0) AS TopAnswerComplexScore,
         COALESCE(ra.AdjustedScore, 0) AS TopAdjustedScore,
         COALESCE(ra.AnswererId, -1) AS TopAnswererId,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCount,
         (SELECT AVG(COALESCE(v.BountyAmount, 0)) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 8) AS AvgBounty,
         CASE 
           WHEN q.Tags IS NOT NULL THEN string_agg(distinct tag, ';') 
           FROM unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag
         ELSE NULL END AS UniqueTagList
  FROM Posts q
  LEFT JOIN AnswererSummaries ra ON ra.QuestionId = q.Id
  WHERE q.PostTypeId = 1 AND q.CreationDate > '2010-01-01'::timestamp
),
UserStats AS (
  SELECT u.Id,
         u.Reputation,
         u.DisplayName,
         COUNT(DISTINCT qs.QuestionId) AS QuestionCount,
         SUM(qs.TopAnswerScore) AS TotalTopScore,
         AVG(qs.TopAnswerComplexScore) AS AvgComplex,
         SUM(qs.TopAdjustedScore) AS TotalAdjusted,
         COUNT(DISTINCT CASE WHEN qs.TopAnswererId = u.Id THEN qs.QuestionId END) AS SelfAnsweredCount,
         qs.UniqueTagList
  FROM Users u
  LEFT JOIN QuestionSummaries qs ON u.Id = qs.OwnerUserId
  GROUP BY u.Id, u.Reputation, u.DisplayName
  HAVING COUNT(DISTINCT qs.QuestionId) > 0
),
BadgeAgg AS (
  SELECT b.UserId,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeCount
  FROM Badges b
  GROUP BY b.UserId
)
SELECT us.Id,
       us.Reputation,
       us.DisplayName,
       us.QuestionCount,
       us.TotalTopScore,
       us.AvgComplex,
       us.TotalAdjusted,
       us.SelfAnsweredCount,
       ba.GoldCount,
       ba.SilverCount,
       ba.BronzeCount,
       us.UniqueTagList,
       RANK() OVER (ORDER BY us.TotalTopScore DESC) AS ScoreRank,
       CASE WHEN us.TotalTopScore > 100 THEN 'High' 
            WHEN us.TotalTopScore > 10 THEN 'Medium' 
            ELSE 'Low' END AS ScoreCategory,
       COALESCE(us.TotalAdjusted / NULLIF(us.QuestionCount, 0), 0) AS AvgAdjustedPerQuestion
FROM UserStats us
LEFT JOIN BadgeAgg ba ON us.Id = ba.UserId
ORDER BY us.TotalTopScore DESC, us.Reputation DESC
LIMIT 500;