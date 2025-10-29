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
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) UP ON UP.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) DP ON DP.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
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
    NULLIF(bp.Title, '') AS CleanTitle,
    CASE
      WHEN bp.Score > 0 THEN bp.Score * 1.0
      ELSE bp.Score * 0.5
    END AS ScoreWeighted,
    -- compute tag count by removing leading '<', splitting on '><' pattern and counting elements
    CASE
      WHEN bp.Tags IS NULL OR bp.Tags = '' THEN 0
      ELSE array_length(string_to_array(trim(both '<>' FROM bp.Tags), '><'), 1)
    END AS TagCount,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = bp.OwnerUserId) AS AvgOwnerScore
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
    cp.PostId,
    cp.OwnerUserId,
    cp.Title,
    cp.Tags,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.Score,
    cp.ViewCount,
    cp.CommentCount,
    cp.AnswerCount,
    cp.UpVotesFromVotes,
    cp.DownVotesFromVotes,
    cp.OwnerName,
    cp.CleanTitle,
    cp.ScoreWeighted,
    cp.TagCount,
    cp.AvgOwnerScore,
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