WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    u.Reputation AS OwnerReputation,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCountDetail
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN Comments c ON p.Id = c.PostId
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  GROUP BY
    p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount,
    p.OwnerUserId, p.LastActivityDate, p.CommentCount, p.AnswerCount, u.Reputation
),
TagUsage AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    p.Id AS PostId
  FROM Tags t
  JOIN Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE t.IsModeratorOnly = FALSE
),
Combined AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.OwnerReputation,
    r.UpVotes,
    r.DownVotes,
    r.CommentCountDetail,
    ROW_NUMBER() OVER (
      PARTITION BY r.OwnerUserId
      ORDER BY r.Score DESC, r.ViewCount DESC, r.LastActivityDate DESC
    ) AS rn_by_owner
  FROM RecentTopQuestions r
  LEFT JOIN TagUsage t ON r.PostId = t.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.LastActivityDate,
  c.CommentCount,
  c.AnswerCount,
  c.OwnerReputation,
  c.UpVotes,
  c.DownVotes,
  c.CommentCountDetail,
  u.DisplayName AS OwnerDisplayName,
  b.Name AS BadgeName,
  b.Date AS BadgeDate,
  pv.VoteTypeName AS PrimaryVoteType,
  CASE
    WHEN c.Score > 0 AND c.ViewCount > 100 THEN 'Hot'
    WHEN c.Score <= 0 THEN 'Unpopular'
    ELSE 'Featured'
  END AS StatusLabel,
  c.rn_by_owner
FROM Combined c
LEFT JOIN Users u ON c.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
  SELECT Id, Name AS VoteTypeName
  FROM VoteTypes
) pv ON 1=1
GROUP BY
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.LastActivityDate,
  c.CommentCount,
  c.AnswerCount,
  c.OwnerReputation,
  c.UpVotes,
  c.DownVotes,
  c.CommentCountDetail,
  u.DisplayName,
  b.Name,
  b.Date,
  pv.VoteTypeName,
  c.rn_by_owner
ORDER BY c.rn_by_owner ASC
LIMIT 100;