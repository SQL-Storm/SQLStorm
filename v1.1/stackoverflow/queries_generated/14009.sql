-- {"query": "14009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 23350, "output_tokens": 10082} 
WITH cte AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS IsBadgeTagBased,
    l.Name AS LinkTypeName,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.CreationDate AS CommentCreationDate,
    c.UserDisplayName AS CommentUserDisplayName,
    c.UserId AS CommentUserId,
    c.ContentLicense AS CommentContentLicense,
    pt.Name AS PostTypeName,
    cr.Name AS CloseReasonName,
    vt.Name AS VoteTypeName,
    ph.Id AS PostHistoryId,
    ph.PostHistoryTypeId,
    ph.RevisionGUID,
    ph.CreationDate AS PostHistoryCreationDate,
    ph.UserId AS PostHistoryUserId,
    ph.UserDisplayName AS PostHistoryUserDisplayName,
    ph.Comment AS PostHistoryComment,
    ph.Text AS PostHistoryText,
    ph.ContentLicense AS PostHistoryContentLicense,
    pl.Id AS PostLinkId,
    pl.CreationDate AS PostLinkCreationDate,
    pl.RelatedPostId,
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired,
    v.Id AS VoteId,
    v.VoteTypeId,
    v.UserId AS VoteUserId,
    v.CreationDate AS VoteCreationDate,
    v.BountyAmount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes l ON pl.LinkTypeId = l.Id
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN CloseReasonTypes cr ON p.ClosedDate IS NOT NULL AND JSON_CONTAINS(ph.Text, CAST(cr.Id AS CHAR), '$.OriginalQuestionIds')
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  LEFT JOIN Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  LEFT JOIN Votes v ON p.Id = v.PostId
),
ranked_cte AS (
  SELECT 
    *,
    RANK() OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate DESC) AS activity_rank
  FROM cte p
)
SELECT 
  *
FROM ranked_cte
WHERE activity_rank = 1
ORDER BY p.LastActivityDate DESC
LIMIT 10;