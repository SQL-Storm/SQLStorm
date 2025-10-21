-- {"query": "14077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1031}
WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Tags,
    CASE
      WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId
      ELSE p.ParentId
    END AS ParentId,
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    DATEDIFF(u.LastAccessDate, u.CreationDate) AS UserActiveDays,
    COALESCE(b.Name, '') AS BadgeName,
    COALESCE(b.Class, 0) AS BadgeClass,
    COALESCE(b.Date, p.CreationDate) AS BadgeDate,
    COALESCE(b.TagBased, 0) AS IsTagBadge,
    COALESCE(c.Id, 0) AS CommentId,
    COALESCE(c.Score, 0) AS CommentScore,
    COALESCE(c.CreationDate, p.CreationDate) AS CommentCreationDate,
    COALESCE(c.UserId, -1) AS CommentUserId,
    COALESCE(c.UserDisplayName, p.OwnerDisplayName) AS CommentUserDisplayName,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END AS PostStatus,
    DATEDIFF(COALESCE(p.ClosedDate, p.LastActivityDate), p.CreationDate) AS PostDays,
    CASE
      WHEN p.PostTypeId = 1 THEN p.Title
      ELSE (
        SELECT p2.Title
        FROM Posts p2
        WHERE p2.Id = p.ParentId
      )
    END AS ParentTitle
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Comments c ON p.Id = c.PostId
),
ranked_comments AS (
  SELECT
    PostId,
    CommentId,
    CommentScore,
    CommentCreationDate,
    CommentUserId,
    CommentUserDisplayName,
    ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CommentCreationDate) AS CommentRank
  FROM cte
)
SELECT
  PostId,
  PostTypeId,
  CreationDate,
  Score,
  ViewCount,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  REGEXP_REPLACE(Tags, '><', ',') AS TagList,
  ParentId,
  UserId,
  Reputation,
  UserCreationDate,
  LastAccessDate,
  UserViews,
  UserUpVotes,
  UserDownVotes,
  UserActiveDays,
  BadgeName,
  BadgeClass,
  BadgeDate,
  IsTagBadge,
  (SELECT STRING_AGG(CommentScore, ',') FROM ranked_comments rc WHERE rc.PostId = c.PostId AND rc.CommentRank <= 3) AS TopCommentScores,
  (SELECT STRING_AGG(CommentUserDisplayName, ',') FROM ranked_comments rc WHERE rc.PostId = c.PostId AND rc.CommentRank <= 3) AS TopCommentUsers,
  PostStatus,
  PostDays,
  ParentTitle
FROM cte c
ORDER BY PostId;
