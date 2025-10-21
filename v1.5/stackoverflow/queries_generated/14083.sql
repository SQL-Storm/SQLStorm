-- {"query": "14083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 196140, "output_tokens": 84976} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.OwnerUserId,
    COALESCE(u.Reputation, 0) AS Reputation,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastEditDate,
    p.LastActivityDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Tags,
    CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END AS AnswerCount,
    CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
    CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentId,
    CASE WHEN p.PostTypeId IN (4, 5) THEN p.Title ELSE NULL END AS TagTitle,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS FavoriteCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
badges AS (
  SELECT 
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  cte.Id,
  cte.PostTypeId,
  cte.OwnerUserId,
  cte.Reputation,
  cte.OwnerDisplayName,
  cte.Score,
  cte.ViewCount,
  cte.CreationDate,
  cte.LastEditDate,
  cte.LastActivityDate,
  cte.ClosedDate,
  cte.CommunityOwnedDate,
  cte.Tags,
  cte.AnswerCount,
  cte.AcceptedAnswerId,
  cte.ParentId,
  cte.TagTitle,
  cte.CommentCount,
  cte.UpVoteCount,
  cte.DownVoteCount,
  cte.FavoriteCount,
  badges.GoldBadgeCount,
  badges.SilverBadgeCount,
  badges.BronzeBadgeCount,
  CASE
    WHEN cte.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN cte.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN cte.PostTypeId = 1 THEN 'Question'
    WHEN cte.PostTypeId = 2 THEN 'Answer'
    WHEN cte.PostTypeId IN (4, 5) THEN 'Tag Wiki'
    ELSE 'Other'
  END AS PostType,
  DATEDIFF(cte.LastActivityDate, cte.CreationDate) AS DaysSinceCreation,
  DATEDIFF(COALESCE(cte.ClosedDate, cte.CommunityOwnedDate, CURRENT_TIMESTAMP), cte.CreationDate) AS DaysSinceLastActivity,
  CASE
    WHEN cte.ClosedDate IS NOT NULL THEN DATEDIFF(cte.ClosedDate, cte.CreationDate)
    WHEN cte.CommunityOwnedDate IS NOT NULL THEN DATEDIFF(cte.CommunityOwnedDate, cte.CreationDate)
    ELSE NULL
  END AS DaysSincePostLifeEvent,
  CASE
    WHEN cte.AcceptedAnswerId IS NOT NULL THEN (
      SELECT p2.Score 
      FROM Posts p2 
      WHERE p2.Id = cte.AcceptedAnswerId
    )
    ELSE NULL
  END AS AcceptedAnswerScore
FROM cte
LEFT JOIN badges ON cte.OwnerUserId = badges.UserId
ORDER BY cte.CreationDate DESC
LIMIT 100;