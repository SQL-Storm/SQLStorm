-- {"query": "22024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1052} 
WITH UserPostStats AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    AVG(COALESCE(p.Score, 0)) AS AvgScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes
  FROM Users u
  LEFT OUTER JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT OUTER JOIN Comments c ON c.UserId = u.Id
  LEFT OUTER JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (2, 3)
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
  SELECT 
    UserId,
    COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
PostDetails AS (
  SELECT 
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.AnswerCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    CASE 
      WHEN p.Tags IS NOT NULL THEN UPPER(SPLIT_PART(SPLIT_PART(p.Tags, '><', 1), '><', 1))
      ELSE 'UNTAGGED'
    END AS FirstTag,
    LENGTH(COALESCE(p.Body, '')) AS BodyLength
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 0
),
CorrelatedSub AS (
  SELECT 
    pd.PostId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pd.PostId) AS CommentCount,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = pd.OwnerUserId AND PostTypeId IN (1,2)) AS OwnerAvgScore
  FROM PostDetails pd
)
SELECT 
  ups.UserId,
  ups.DisplayName,
  ups.Reputation,
  ups.TotalPosts,
  ups.Questions,
  ups.Answers,
  ups.AvgScore,
  ups.TotalViews,
  ups.TotalComments,
  ups.TotalVotes,
  bc.GoldBadges,
  bc.SilverBadges,
  bc.BronzeBadges,
  pd.PostId,
  pd.Title,
  pd.FirstTag,
  pd.Score,
  pd.UpVotes,
  pd.DownVotes,
  pd.BodyLength,
  cs.CommentCount,
  cs.OwnerAvgScore,
  RANK() OVER (PARTITION BY ups.UserId ORDER BY pd.Score DESC) AS PostRank,
  DENSE_RANK() OVER (ORDER BY ups.TotalPosts DESC) AS UserRank,
  CONCAT(ups.DisplayName, ' has ', COALESCE(ups.TotalPosts, 0), ' posts') AS UserDesc
FROM UserPostStats ups
LEFT OUTER JOIN BadgeCounts bc ON bc.UserId = ups.UserId
INNER JOIN PostDetails pd ON pd.OwnerUserId = ups.UserId
INNER JOIN CorrelatedSub cs ON cs.PostId = pd.PostId
WHERE ups.Reputation > 1000 OR EXISTS (
  SELECT 1 FROM Badges b WHERE b.UserId = ups.UserId AND b.Class = 1
) UNION ALL
SELECT 
  ups.UserId,
  ups.DisplayName,
  ups.Reputation,
  ups.TotalPosts,
  ups.Questions,
  ups.Answers,
  ups.AvgScore,
  ups.TotalViews,
  ups.TotalComments,
  ups.TotalVotes,
  bc.GoldBadges,
  bc.SilverBadges,
  bc.BronzeBadges,
  NULL AS PostId,
  NULL AS Title,
  NULL AS FirstTag,
  NULL AS Score,
  NULL AS UpVotes,
  NULL AS DownVotes,
  NULL AS BodyLength,
  NULL AS CommentCount,
  NULL AS OwnerAvgScore,
  NULL AS PostRank,
  DENSE_RANK() OVER (ORDER BY ups.TotalPosts DESC) AS UserRank,
  CONCAT(ups.DisplayName, ' (no eligible posts)') AS UserDesc
FROM UserPostStats ups
LEFT OUTER JOIN BadgeCounts bc ON bc.UserId = ups.UserId
WHERE ups.TotalPosts = 0 AND NOT EXISTS (
  SELECT 1 FROM PostDetails pd WHERE pd.OwnerUserId = ups.UserId
)
ORDER BY UserRank, PostRank NULLS LAST;