-- {"query": "44088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 201872, "output_tokens": 69338} 

WITH CTE AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Score,
    p.Tags,
    u.Reputation,
    u.AccountId,
    u.EmailHash,
    u.ProfileImageUrl,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeType,
    b.Date AS BadgeDate,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    CASE
      WHEN v.VoteTypeId = 2 THEN 1
      WHEN v.VoteTypeId = 3 THEN -1
      ELSE 0
    END AS VoteScore
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Votes v ON p.Id = v.PostId
)
SELECT
  PostId,
  PostTypeId,
  CreationDate,
  OwnerUserId,
  ViewCount,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  Score,
  Tags,
  Reputation,
  AccountId,
  EmailHash,
  ProfileImageUrl,
  BadgeName,
  BadgeClass,
  BadgeType,
  BadgeDate,
  SUM(VoteScore) AS VoteScore
FROM CTE
GROUP BY
  PostId,
  PostTypeId,
  CreationDate,
  OwnerUserId,
  ViewCount,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  Score,
  Tags,
  Reputation,
  AccountId,
  EmailHash,
  ProfileImageUrl,
  BadgeName,
  BadgeClass,
  BadgeType,
  BadgeDate
ORDER BY
  PostId,
  CreationDate DESC;
