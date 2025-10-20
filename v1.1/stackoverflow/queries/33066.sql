-- {"query": "33066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 701} 
WITH Post_Statistics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    u.Id AS OwnerId,
    u.Reputation,
    u.DisplayName AS OwnerName,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    ht.Name AS PostHistoryType,
    ph.CreationDate AS HistoryChangeDate,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    vt.Name AS VoteTypeName,
    c.Id AS CommentId,
    c.CreationDate AS CommentCreationDate,
    c.UserDisplayName AS CommentUser,
    c.Score AS CommentScore
  FROM
    Posts p
  LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
  LEFT JOIN
    Badges b ON u.Id = b.UserId
  LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId
  LEFT JOIN
    PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
  LEFT JOIN
    Votes v ON p.Id = v.PostId
  LEFT JOIN
    VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN
    Comments c ON p.Id = c.PostId
)
SELECT
  ps.PostId,
  ps.PostTypeId,
  ps.Title,
  ps.CreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.Tags,
  ps.OwnerId,
  ps.Reputation,
  ps.OwnerName,
  ps.UserCreationDate,
  ps.UserLastAccessDate,
  ps.UserViews,
  ps.UserUpVotes,
  ps.UserDownVotes,
  COUNT(DISTINCT ps.BadgeId) AS TotalBadges,
  STRING_AGG(DISTINCT ps.BadgeName, ', ') AS BadgeNames,
  COUNT(DISTINCT ps.PostHistoryType) AS PostHistoryEvents,
  MAX(ps.HistoryChangeDate) AS LastHistoryChange,
  COUNT(DISTINCT ps.VoteTypeId) AS TotalVotes,
  COUNT(DISTINCT ps.VoteTypeName) AS VoteTypesCount,
  COUNT(DISTINCT ps.CommentId) AS TotalComments,
  MAX(ps.CommentCreationDate) AS LastCommentDate
FROM
  Post_Statistics ps
GROUP BY
  ps.PostId,
  ps.PostTypeId,
  ps.Title,
  ps.CreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.Tags,
  ps.OwnerId,
  ps.Reputation,
  ps.OwnerName,
  ps.UserCreationDate,
  ps.UserLastAccessDate,
  ps.UserViews,
  ps.UserUpVotes,
  ps.UserDownVotes
ORDER BY
  TotalVotes DESC,
  LastCommentDate DESC
LIMIT 100;