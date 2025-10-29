-- {"query": "4284.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1711}
WITH RelevantPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.Title,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    pt.Name AS PostTypeName,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostTypeOrder
  FROM Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.CreationDate >= DATE '2023-01-01'
    AND p.PostTypeId IN (1, 2)
), PostCommentCounts AS (
  SELECT
    PostId,
    COUNT(Id) AS CommentCountByPost
  FROM Comments
  GROUP BY
    PostId
), PostVoteSummary AS (
  SELECT
    PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(Id) AS TotalVoteCount
  FROM Votes
  WHERE
    VoteTypeId IN (2, 3)
  GROUP BY
    PostId
), UserPostActivity AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(Id) AS PostCount,
    AVG(Score) AS AvgPostScore,
    MAX(CreationDate) AS LastPostDate
  FROM Posts
  WHERE
    OwnerUserId IS NOT NULL
  GROUP BY
    OwnerUserId
), RecentHotQuestions AS (
  SELECT
    Id,
    Title,
    Score,
    ROW_NUMBER() OVER (ORDER BY Score DESC) AS HotnessRank
  FROM Posts
  WHERE
    PostTypeId = 1
    AND Score > 1000
    AND CreationDate BETWEEN DATE '2023-06-01' AND DATE '2023-07-01'
)
SELECT
  rp.Id AS PostId,
  rp.PostTypeName,
  rp.Title,
  rp.PostCreationDate,
  rp.PostScore,
  rp.ScoreRank,
  rp.OwnerDisplayName,
  rp.OwnerReputation,
  rp.AnswerCount,
  rp.CommentCount AS PostLevelCommentCount,
  COALESCE(pcc.CommentCountByPost, 0) AS TotalComments,
  pvs.UpVoteCount,
  pvs.DownVoteCount,
  pvs.TotalVoteCount,
  COALESCE(rp.FavoriteCount, 0) AS Favorites,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN u.CreationDate < rp.PostCreationDate - INTERVAL '1 year' AND u.Id IS NOT NULL THEN 'Old User'
    ELSE 'Newer User'
  END AS UserAgeCategory,
  up.PostCount AS UserTotalPosts,
  up.AvgPostScore AS UserAvgScore,
  COALESCE(rhq.HotnessRank, 9999) AS RecentHotRank,
  CONCAT(
    COALESCE(rp.Title, 'No Title'),
    ' (',
    rp.PostTypeName,
    ') - ',
    CASE
      WHEN rp.PostScore > 50 THEN 'High Score'
      WHEN rp.PostScore < 0 THEN 'Negative Score'
      ELSE 'Moderate Score'
    END,
    ' - User: ',
    rp.OwnerDisplayName
  ) AS CompositePostDescription,
  rp.PostTypeOrder
FROM RelevantPosts rp
LEFT JOIN PostCommentCounts pcc
  ON rp.Id = pcc.PostId
LEFT JOIN PostVoteSummary pvs
  ON rp.Id = pvs.PostId
LEFT JOIN UserPostActivity up
  ON rp.OwnerUserId = up.UserId
LEFT JOIN RecentHotQuestions rhq
  ON rp.Id = rhq.Id
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
WHERE
  rp.PostScore > 0
  AND COALESCE(pcc.CommentCountByPost, 0) < 10
  AND (
    rp.OwnerReputation > 1000 OR rp.OwnerUserId IS NULL
  )
UNION
SELECT
  rp.Id AS PostId,
  rp.PostTypeName,
  rp.Title,
  rp.PostCreationDate,
  rp.PostScore,
  rp.ScoreRank,
  rp.OwnerDisplayName,
  rp.OwnerReputation,
  rp.AnswerCount,
  rp.CommentCount AS PostLevelCommentCount,
  COALESCE(pcc.CommentCountByPost, 0) AS TotalComments,
  pvs.UpVoteCount,
  pvs.DownVoteCount,
  pvs.TotalVoteCount,
  COALESCE(rp.FavoriteCount, 0) AS Favorites,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN u.CreationDate < rp.PostCreationDate - INTERVAL '1 year' AND u.Id IS NOT NULL THEN 'Old User'
    ELSE 'Newer User'
  END AS UserAgeCategory,
  up.PostCount AS UserTotalPosts,
  up.AvgPostScore AS UserAvgScore,
  COALESCE(rhq.HotnessRank, 9999) AS RecentHotRank,
  CONCAT(
    COALESCE(rp.Title, 'No Title'),
    ' (',
    rp.PostTypeName,
    ') - ',
    CASE
      WHEN rp.PostScore > 50 THEN 'High Score'
      WHEN rp.PostScore < 0 THEN 'Negative Score'
      ELSE 'Moderate Score'
    END,
    ' - User: ',
    rp.OwnerDisplayName
  ) AS CompositePostDescription,
  rp.PostTypeOrder
FROM RelevantPosts rp
LEFT JOIN PostCommentCounts pcc
  ON rp.Id = pcc.PostId
LEFT JOIN PostVoteSummary pvs
  ON rp.Id = pvs.PostId
LEFT JOIN UserPostActivity up
  ON rp.OwnerUserId = up.UserId
LEFT JOIN RecentHotQuestions rhq
  ON rp.Id = rhq.Id
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
WHERE
  rp.PostScore <= 0
  AND COALESCE(pcc.CommentCountByPost, 0) >= 10
  AND (
    rp.OwnerReputation <= 1000 AND rp.OwnerUserId IS NOT NULL
  )
ORDER BY
  PostCreationDate DESC,
  PostId,
  PostTypeName,
  Title,
  PostScore,
  ScoreRank,
  OwnerDisplayName,
  OwnerReputation,
  AnswerCount,
  PostLevelCommentCount,
  TotalComments,
  UpVoteCount,
  DownVoteCount,
  TotalVoteCount,
  Favorites,
  PostStatus,
  UserAgeCategory,
  UserTotalPosts,
  UserAvgScore,
  RecentHotRank,
  CompositePostDescription,
  PostTypeOrder;