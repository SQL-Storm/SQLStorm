WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         u.Id AS UserId, u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes,
         b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased,
         COALESCE(NULLIF(
           CASE
             WHEN p.Tags IS NULL OR p.Tags = '' THEN ''
             WHEN POSITION('><' IN p.Tags) > 0 THEN SUBSTRING(p.Tags FROM 1 FOR POSITION('><' IN p.Tags) - 1)
             ELSE p.Tags
           END
         , ''), '') AS MainTag,
         CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS PostType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE p.PostTypeId IN (1, 2)
)
SELECT
  cte.Id,
  cte.PostTypeId,
  cte.ParentId,
  cte.CreationDate,
  cte.Score,
  cte.AnswerCount,
  cte.CommentCount,
  cte.FavoriteCount,
  cte.ClosedDate,
  cte.CommunityOwnedDate,
  cte.UserId,
  cte.Reputation,
  cte.UserCreationDate,
  cte.LastAccessDate,
  cte.Views,
  cte.UpVotes,
  cte.DownVotes,
  cte.BadgeId,
  cte.BadgeName,
  cte.BadgeDate,
  cte.BadgeClass,
  cte.BadgeTagBased,
  cte.MainTag,
  cte.PostType,
  DENSE_RANK() OVER (PARTITION BY cte.UserId ORDER BY cte.Reputation DESC) AS UserReputationRank,
  cast('2024-10-01' as date) - cte.UserCreationDate AS UserAge,
  cast('2024-10-01' as date) - cte.CreationDate AS PostAge,
  CASE
    WHEN cte.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN cte.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN cte.ParentId IS NOT NULL THEN 'Answer'
    ELSE 'Question'
  END AS PostStatus,
  COALESCE(cte.ClosedDate - cte.CreationDate, cast('2024-10-01' as date) - cte.CreationDate) AS DaysSincePostCreation,
  CASE
    WHEN cte.BadgeClass = 1 THEN 'Gold'
    WHEN cte.BadgeClass = 2 THEN 'Silver'
    WHEN cte.BadgeClass = 3 THEN 'Bronze'
    ELSE NULL
  END AS BadgeClass,
  CASE
    WHEN COALESCE(cte.BadgeTagBased, FALSE) = TRUE THEN 'Tag-Based'
    ELSE 'Named'
  END AS BadgeType
FROM cte
GROUP BY
  cte.Id,
  cte.PostTypeId,
  cte.ParentId,
  cte.CreationDate,
  cte.Score,
  cte.AnswerCount,
  cte.CommentCount,
  cte.FavoriteCount,
  cte.ClosedDate,
  cte.CommunityOwnedDate,
  cte.UserId,
  cte.Reputation,
  cte.UserCreationDate,
  cte.LastAccessDate,
  cte.Views,
  cte.UpVotes,
  cte.DownVotes,
  cte.BadgeId,
  cte.BadgeName,
  cte.BadgeDate,
  cte.BadgeClass,
  cte.BadgeTagBased,
  cte.MainTag,
  cte.PostType
ORDER BY cte.Id;