-- {"query": "5174.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 899} 
WITH top_posters AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    COALESCE(UP.VoteCount, 0) AS UpVotesFromVotes,
    COALESCE(DP.VoteCount, 0) AS DownVotesFromVotes
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 2 -- UpMod
    GROUP BY PostId
  ) UP ON UP.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3 -- DownMod
    GROUP BY PostId
  ) DP ON DP.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
complex_filters AS (
  SELECT
    bp.PostId,
    bp.OwnerUserId,
    bp.Title,
    bp.Tags,
    bp.CreationDate,
    bp.LastActivityDate,
    bp.Score,
    bp.ViewCount,
    bp.CommentCount,
    bp.AnswerCount,
    bp.UpVotesFromVotes,
    bp.DownVotesFromVotes,
    U.DisplayName AS OwnerName,
    NULLIF(b.Title, '') AS CleanTitle,
    CASE
      WHEN bp.Score > 0 THEN bp.Score * 1.0
      ELSE bp.Score * 0.5
    END AS ScoreWeighted,
    ARRAY_LENGTH(string_to_array(REPLACE(bp.Tags, '<', ''), '>') , 1) AS TagCount,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = bp.OwnerUserId) AS AvgOwnerScore
  FROM recent_activity bp
  LEFT JOIN Users U ON U.Id = bp.OwnerUserId
),
cte_post_links AS (
  SELECT
    cl.PostId,
    cl.RelatedPostId,
    cl.LinkTypeId,
    l.Name AS LinkTypeName
  FROM PostLinks cl
  JOIN LinkTypes l ON l.Id = cl.LinkTypeId
  WHERE cl.LinkTypeId IN (1,3)
),
correlated_comments AS (
  SELECT
    c.PostId,
    AVG(CASE WHEN c.UserId IS NULL THEN 0 ELSE c.Score END) AS AvgCommentScore,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
windowed AS (
  SELECT
    cp.*,
    ROW_NUMBER() OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.LastActivityDate DESC) AS rn_owner
  FROM complex_filters cp
)
SELECT
  w.PostId,
  w.OwnerUserId,
  w.OwnerName,
  w.Title AS PostTitle,
  w.Tags,
  w.CreationDate,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.AnswerCount,
  w.UpVotesFromVotes,
  w.DownVotesFromVotes,
  w.ScoreWeighted,
  w.TagCount,
  w.AvgOwnerScore,
  cq.AvgCommentScore,
  cq.CommentCount AS TotalCommentsForPost,
  cl.RelatedPostId,
  cl.LinkTypeName,
  u.Reputation AS UserReputation,
  u.AccountId
FROM windowed w
LEFT JOIN correlated_comments cq ON cq.PostId = w.PostId
LEFT JOIN cte_post_links cl ON cl.PostId = w.PostId
LEFT JOIN Users u ON u.Id = w.OwnerUserId
WHERE w.rn_owner = 1
  AND (w.TagCount IS NULL OR w.TagCount > 0)
  AND (w.AvgOwnerScore IS NULL OR w.AvgOwnerScore > 5)
ORDER BY w.LastActivityDate DESC
LIMIT 200;