WITH
RecentSignificantVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    t.Name AS VoteTypeName,
    u.DisplayName AS VoterName
  FROM Votes v
  JOIN VoteTypes t ON v.VoteTypeId = t.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.VoteTypeId IN (2,3,10,12,14,15,16)
    AND v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(v.PostId) FILTER (WHERE v.PostId IS NOT NULL) AS TagMentions,
    AVG(p.ViewCount) AS AvgViews,
    SUM(p.Score) AS TotalScore
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY t.TagName
),
TopQuestionActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    pt.Name AS PostTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE pt.Name = 'Question'
),
Combined AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    qq.DisplayName AS OwnerDisplayName,
    q.PostTypeName,
    ROW_NUMBER() OVER (ORDER BY q.LastActivityDate DESC, q.Score DESC) AS seq
  FROM TopQuestionActivity q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Users qq ON u.Id = qq.Id
  LEFT JOIN PostTypes qt ON q.PostTypeName = qt.Name
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Tags,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.PostTypeName,
  c.seq,
  (SELECT COUNT(*) FROM Comments co WHERE co.PostId = c.PostId) AS CommentCountTotal,
  (SELECT MAX(v2.CreationDate) FROM Votes v2 WHERE v2.PostId = c.PostId AND v2.VoteTypeId = 2) AS LastUpvoteDate,
  (SELECT STRING_AGG(uc.DisplayName, ', ') FROM Votes v3 JOIN Users uc ON v3.UserId = uc.Id WHERE v3.PostId = c.PostId AND v3.VoteTypeId = 2) AS Upvoters,
  ta.TagName,
  ta.TotalScore
FROM Combined c
LEFT JOIN LATERAL (
  SELECT vt.Name AS TypeCat
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.PostId = c.PostId
  ORDER BY v.CreationDate DESC
  LIMIT 1
) AS lastvote ON true
LEFT JOIN RecentSignificantVotes rsv ON rsv.PostId = c.PostId
LEFT JOIN TagActivity ta ON ta.TagName ILIKE '%' || REGEXP_REPLACE(c.Tags, '[<>]', '', 'g') || '%'
WHERE c.LastActivityDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
  AND (ta.TagName IS NULL OR ta.TotalScore > 0)
GROUP BY
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Tags,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.PostTypeName,
  c.seq,
  ta.TagName,
  ta.TotalScore
ORDER BY c.LastActivityDate DESC, c.Score DESC
FETCH FIRST 100 ROWS ONLY;