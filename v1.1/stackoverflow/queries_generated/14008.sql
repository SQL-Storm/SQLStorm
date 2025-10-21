-- {"query": "14008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 976}
WITH cte1 AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE p.ParentId END AS ParentId,
         CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 2 END AS PostType,
         COALESCE(NULLIF(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), ''), '') AS TagList
  FROM Posts p
),
cte2 AS (
  SELECT c.Id, c.PostId, c.Score, c.CreationDate, c.UserId
  FROM Comments c
),
cte3 AS (
  SELECT b.Id, b.UserId, b.Name, b.Date, b.Class, b.TagBased
  FROM Badges b
),
cte4 AS (
  SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Comment, ph.Text
  FROM PostHistory ph
),
cte5 AS (
  SELECT pl.Id, pl.PostId, pl.RelatedPostId, pl.LinkTypeId, pl.CreationDate
  FROM PostLinks pl
),
cte6 AS (
  SELECT v.Id, v.PostId, v.VoteTypeId, v.UserId, v.CreationDate, v.BountyAmount
  FROM Votes v
)
SELECT
  cte1.Id, cte1.PostTypeId, cte1.OwnerUserId, cte1.CreationDate, cte1.LastActivityDate, cte1.Tags, cte1.AnswerCount, cte1.CommentCount, cte1.FavoriteCount, cte1.ClosedDate, cte1.CommunityOwnedDate, cte1.ParentId, cte1.PostType, cte1.TagList,
  cte2.Id AS CommentId, cte2.Score AS CommentScore, cte2.CreationDate AS CommentCreationDate, cte2.UserId AS CommentUserId,
  cte3.Id AS BadgeId, cte3.UserId AS BadgeUserId, cte3.Name AS BadgeName, cte3.Date AS BadgeDate, cte3.Class AS BadgeClass, cte3.TagBased AS BadgeTagBased,
  cte4.PostHistoryTypeId, cte4.CreationDate AS PostHistoryCreationDate, cte4.UserId AS PostHistoryUserId, cte4.Comment AS PostHistoryComment, cte4.Text AS PostHistoryText,
  cte5.Id AS PostLinkId, cte5.RelatedPostId, cte5.LinkTypeId, cte5.CreationDate AS PostLinkCreationDate,
  cte6.Id AS VoteId, cte6.VoteTypeId, cte6.UserId AS VoteUserId, cte6.CreationDate AS VoteCreationDate, cte6.BountyAmount AS VoteBountyAmount
FROM cte1
LEFT JOIN cte2 ON cte1.Id = cte2.PostId
LEFT JOIN cte3 ON cte1.OwnerUserId = cte3.UserId
LEFT JOIN cte4 ON cte1.Id = cte4.PostId
LEFT JOIN cte5 ON cte1.Id = cte5.PostId
LEFT JOIN cte6 ON cte1.Id = cte6.PostId
ORDER BY cte1.Id, cte2.Id, cte3.Id, cte4.Id, cte5.Id, cte6.Id;
