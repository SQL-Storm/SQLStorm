WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    vt.Id AS VoteTypeId,
    vt.Name AS VoteTypeName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
),
Filtered AS (
  SELECT
    PostId,
    Title,
    Tags,
    CreationDate,
    OwnerUserId,
    LastActivityDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    PostTypeId,
    Reputation,
    OwnerDisplayName,
    Location,
    Views,
    UpVotes,
    DownVotes,
    VoteTypeId,
    VoteTypeName,
    rn
  FROM RankedPosts
  WHERE rn = 1
),
Correlated AS (
  SELECT
    f.PostId,
    f.Title,
    f.Tags,
    f.CreationDate,
    f.OwnerUserId,
    f.LastActivityDate,
    f.Score,
    f.ViewCount,
    f.AnswerCount,
    f.CommentCount,
    f.FavoriteCount,
    f.PostTypeId,
    f.Reputation,
    f.OwnerDisplayName,
    f.Location,
    f.Views,
    f.UpVotes,
    f.DownVotes,
    f.VoteTypeId,
    f.VoteTypeName
  FROM Filtered f
  LEFT JOIN PostLinks pl ON pl.PostId = f.PostId
  LEFT JOIN Posts r ON pl.RelatedPostId = r.Id
  WHERE (f.Tags LIKE '%<example>%'
         OR f.Title LIKE '%benchmark%')
    OR (EXTRACT(year FROM f.CreationDate) = EXTRACT(year FROM CAST('2024-10-01' AS date))
        AND f.Reputation > 1000)
),
VoteSummaries AS (
  SELECT
    v.PostId,
    STRING_AGG(vt.Name || ':' || COALESCE(CAST(v.BountyAmount AS varchar), ''), '|' ORDER BY vt.Name, v.BountyAmount) AS VoteSummary
  FROM Votes v
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
)
SELECT
  p.PostId,
  p.Title,
  p.Tags,
  p.CreationDate,
  p.OwnerUserId,
  p.OwnerDisplayName,
  p.Location,
  p.Reputation,
  p.ViewCount,
  p.Score AS PostScore,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.LastActivityDate,
  p.Views,
  p.UpVotes,
  p.DownVotes,
  p.VoteTypeName AS LastVoteType,
  vs.VoteSummary,
  (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId) AS AvgOwnerScore,
  (SELECT COUNT(*) FROM PostLinks WHERE PostId = p.PostId) AS LinkCount,
  (SELECT COUNT(*) FROM Comments WHERE PostId = p.PostId) AS CommentCountTotal
FROM Correlated p
LEFT JOIN VoteSummaries vs ON vs.PostId = p.PostId
ORDER BY p.LastActivityDate DESC
LIMIT 100;