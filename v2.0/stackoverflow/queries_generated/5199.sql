-- {"query": "5199.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 844} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.CloseReasonTypesId,
    p.LastEditorUserId,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn_post
  FROM Posts p
  LEFT JOIN (SELECT Id, Name
             FROM PostHistoryTypes) pht ON 1=1
)
, author_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Views,0) AS Views,
    COALESCE(u.UpVotes,0) AS UpVotes,
    COALESCE(u.DownVotes,0) AS DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.ProfileImageUrl,
    u.AccountId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 1) AS QuestionCount
  FROM Users u
)
, flagged_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate,
    STRING_AGG(CONCAT('(', v.VoteTypeId, ':', v.BountyAmount, ')'), ',') WITHIN GROUP (ORDER BY v.CreationDate) AS VotesInline
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE v.VoteTypeId IN (2,6,10,11,12,14,15,16)
  GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, v.VoteTypeId, v.UserId, v.CreationDate, v.BountyAmount
)
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  CASE rp.PostTypeId
    WHEN 1 THEN 'Question'
    WHEN 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  a.DisplayName AS OwnerDisplayName,
  asr.Reputation,
  asr.BadgeCount,
  asr.QuestionCount,
  COALESCE(cf.LastComment, '') AS LastCommentText,
  COALESCE(cf.CommentCount, 0) AS CommentCountForPost,
  ustat.DisplayName AS EditorDisplayName,
  rnk.rank_within_type
FROM recent_activity rp
LEFT JOIN author_stats asr ON rp.OwnerUserId = asr.UserId
LEFT JOIN (
  SELECT c.PostId, MAX(c.CreationDate) AS LastCommentDate, MAX(c.Text) AS LastComment
  FROM Comments c
  GROUP BY c.PostId
) cc ON rp.PostId = cc.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
) cf ON rp.PostId = cf.PostId
LEFT JOIN Users ustat ON rp.OwnerUserId = ustat.Id
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rank_within_type
  FROM Posts p
) rnk ON rp.PostId = rnk.PostId
WHERE rp.rn_post = 1
ORDER BY rp.LastActivityDate DESC
LIMIT 100;