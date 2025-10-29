WITH ranked_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.LastEditDate,
    p.LastEditorUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Id DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
link_summary AS (
  SELECT
    pl.PostId,
    COUNT(*) AS link_count,
    STRING_AGG(CONCAT(lt.Name, '(', lt.Id, ')'), ',') AS link_types
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
vote_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name LIKE 'UpMod%' THEN 1 ELSE 0 END) AS upmod_votes,
    SUM(CASE WHEN vt.Name LIKE 'DownMod%' THEN 1 ELSE 0 END) AS downmod_votes,
    SUM(CASE WHEN vt.Name LIKE 'Close%' THEN 1 ELSE 0 END) AS close_votes,
    SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS accepted_by_originator,
    SUM(v.BountyAmount) AS bounty_amount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
),
tag_info AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
)
SELECT
  rp.Id                                      AS PostId,
  rp.PostTypeId                              AS PostType,
  rp.Title,
  rp.Body,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.Reputation                              AS OwnerReputation,
  rp.UserCreationDate                         AS OwnerCreationDate,
  rp.LastEditorUserId,
  pi.LastEditorDisplayName                    AS LastEditorDisplayName,
  rp.LastEditDate,
  rp.Views,
  rp.Score,
  rp.ViewCount,
  COALESCE(ls.link_count, 0)                 AS LinkCount,
  COALESCE(ls.link_types, '')                AS LinkTypes,
  COALESCE(vs.upmod_votes, 0)                AS UpModVotes,
  COALESCE(vs.downmod_votes, 0)              AS DownModVotes,
  COALESCE(vs.close_votes, 0)                AS CloseVotes,
  COALESCE(vs.accepted_by_originator, 0)     AS AcceptedByOriginator,
  COALESCE(vs.bounty_amount, 0)              AS BountyAmount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.Tags,
  pi.Title AS ParentTitle,
  pc.Name AS ClosedReasonName,
  CASE
    WHEN rp.ParentId IS NOT NULL THEN
      (SELECT p2.Title FROM Posts p2 WHERE p2.Id = rp.ParentId)
    ELSE NULL
  END AS ParentPostTitle,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCountLive,
  PERCENT_RANK() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC) AS ScorePercentile
FROM ranked_posts rp
LEFT JOIN link_summary ls ON rp.Id = ls.PostId
LEFT JOIN vote_summary vs ON rp.Id = vs.PostId
LEFT JOIN Posts pi ON rp.ParentId = pi.Id
LEFT JOIN PostHistory ph ON ph.PostId = rp.Id
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN CloseReasonTypes pc ON ph.Comment LIKE '%' || pc.Id || '%'
GROUP BY
  rp.Id,
  rp.PostTypeId,
  rp.Title,
  rp.Body,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.UserCreationDate,
  rp.LastEditorUserId,
  pi.LastEditorDisplayName,
  rp.LastEditDate,
  rp.Views,
  rp.Score,
  rp.ViewCount,
  ls.link_count,
  ls.link_types,
  vs.upmod_votes,
  vs.downmod_votes,
  vs.close_votes,
  vs.accepted_by_originator,
  vs.bounty_amount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.Tags,
  pi.Title,
  pc.Name,
  rp.ParentId,
  rp.Id -- for scalar subquery referencing rp.Id (keeps it deterministic)
ORDER BY rp.CreationDate DESC, rp.Score DESC, rp.Id
LIMIT 100;