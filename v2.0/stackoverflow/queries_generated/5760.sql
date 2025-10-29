-- {"query": "5760.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 739} 
WITH
MarkedChanges AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesToday,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesToday,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) OVER (PARTITION BY p.Id) AS LastUpVoteDate,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN v.CreationDate END) OVER (PARTITION BY p.Id) AS LastDownVoteDate
  FROM Posts p
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.Tags, p.OwnerUserId, p.LastActivityDate,
    p.PostTypeId, p.ParentId, p.AcceptedAnswerId, p.CommentCount, p.FavoriteCount, p.ContentLicense
),
CorrelatedStats AS (
  SELECT
    m.*,
    u.Reputation,
    u.DisplayName,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    bt.Class,
    bt.Name AS BadgeName,
    b.Date AS BadgeDate
  FROM MarkedChanges m
  LEFT JOIN Users u ON m.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN (SELECT Id, Class, Name FROM Badges) AS bt ON b.Id = bt.Id
),
Windowed AS (
  SELECT
    cs.*,
    ROW_NUMBER() OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.LastActivityDate DESC NULLS_LAST) AS rn_last_activity,
    RANK() OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.Score DESC) AS score_rank
  FROM CorrelatedStats cs
),
Filtered AS (
  SELECT *
  FROM Windowed
  WHERE rn_last_activity = 1 OR score_rank <= 5
)
SELECT
  f.PostId,
  f.Title,
  f.CreationDate,
  f.ViewCount,
  f.Score,
  f.Tags,
  f.OwnerUserId,
  f.DisplayName AS OwnerDisplayName,
  f.LastActivityDate,
  f.PostTypeId,
  f.ParentId,
  f.AcceptedAnswerId,
  f.CommentCount,
  f.FavoriteCount,
  f.ContentLicense,
  f.Reputation AS OwnerReputation,
  f.Location,
  f.AccountId,
  f.BadgeName,
  f.BadgeDate,
  f.LastUpVoteDate,
  f.LastDownVoteDate,
  (f.UpVotesToday - f.DownVotesToday) AS NetVoteDelta,
  CASE
    WHEN f.PostTypeId = 1 THEN 'Question'
    WHEN f.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostTypeLabel
FROM Filtered f
ORDER BY f.LastActivityDate DESC NULLS LAST, f.Score DESC NULLS LAST
LIMIT 200;