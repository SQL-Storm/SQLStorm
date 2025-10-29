WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
recent_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    q.LastActivityDate,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.CreationDate AS UserCreationDate,
    we.DisplayName AS LastEditorName,
    l.Count AS LinkCount,
    pLastEdit.LastEditorUserId AS LastEditorUserId
  FROM recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Posts pLastEdit ON pLastEdit.Id = q.PostId
  LEFT JOIN Users we ON pLastEdit.LastEditorUserId = we.Id
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN (SELECT PostId, COUNT(*) AS Count FROM PostLinks GROUP BY PostId) l ON l.PostId = q.PostId
),
tag_split AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.ViewCount,
    ra.Score,
    ra.OwnerUserId,
    ra.Tags,
    ra.LastActivityDate,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.OwnerDisplayName,
    ra.Reputation,
    ra.Location,
    ra.UserCreationDate,
    ra.LastEditorName,
    ra.LinkCount,
    unnest(string_to_array(substring(ra.Tags, 2, length(ra.Tags)-2), '><')) AS Tag
  FROM recent_activity ra
)
SELECT
  rs.PostId,
  rs.Title,
  rs.CreationDate,
  rs.ViewCount,
  rs.Score,
  rs.OwnerDisplayName,
  rs.Reputation,
  rs.Location,
  rs.LastActivityDate,
  rs.AnswerCount,
  rs.CommentCount,
  rs.FavoriteCount,
  rs.Tag AS TagName,
  CASE
    WHEN rs.AnswerCount > 0 THEN rs.AnswerCount * 2.5
    ELSE rs.Score * 1.75
  END AS EngagementScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY rs.PostId) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY rs.PostId) AS DownVotes,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate ELSE NULL END) OVER (PARTITION BY rs.PostId) AS LastUpVoteDate
FROM tag_split rs
LEFT JOIN Votes v ON v.PostId = rs.PostId
  AND v.CreationDate >= rs.CreationDate
ORDER BY rs.LastActivityDate DESC, rs.Score DESC
LIMIT 200;