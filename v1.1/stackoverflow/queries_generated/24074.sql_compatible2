WITH user_points AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                  WHEN v.VoteTypeId = 3 THEN -1
                  ELSE 0 END) AS vote_points,
         COUNT(c.Id) AS comment_count
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
tag_activity AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Tags,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
         COUNT(c.Id) AS comments,
         CASE
           WHEN POSITION('>' IN p.Tags) > 0 AND POSITION('<' IN p.Tags) > 0 THEN
             SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1)
           ELSE NULL
         END AS TagName,
         ROW_NUMBER() OVER (PARTITION BY
             CASE
               WHEN POSITION('>' IN p.Tags) > 0 AND POSITION('<' IN p.Tags) > 0 THEN
                 SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1)
               ELSE NULL
             END
           ORDER BY p.Score DESC) AS tag_rank
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.Tags, p.Score
),
duplicate_pairs AS (
  SELECT COALESCE(p1.Id, p2.Id) AS PostId,
         p1.OwnerUserId,
         p2.Id AS DuplicateOf
  FROM PostLinks l
  LEFT JOIN Posts p1 ON p1.Id = l.PostId
  LEFT JOIN Posts p2 ON p2.Id = l.RelatedPostId
  WHERE l.LinkTypeId = 3
),
user_badge_activity AS (
  SELECT u.Id AS UserId,
         STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames,
         MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
question_engagement AS (
  SELECT p.Id AS QuestionId,
         p.AcceptedAnswerId,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount,
         COALESCE(uv.user_votes, 0) AS user_votes,
         COALESCE(gc.global_comments, 0) AS global_comments
  FROM Posts p
  LEFT JOIN (
        SELECT ph.PostId, COUNT(1) AS user_votes
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 2
        GROUP BY ph.PostId
  ) uv ON uv.PostId = p.Id
  LEFT JOIN (
        SELECT c.PostId, COUNT(1) AS global_comments
        FROM Comments c
        GROUP BY c.PostId
  ) gc ON gc.PostId = p.Id
  WHERE p.PostTypeId = 1
)
SELECT
  up.UserId,
  up.Reputation,
  up.vote_points,
  ub.BadgeNames,
  ub.LastBadgeDate,
  qa.QuestionId,
  qa.AcceptedAnswerId,
  qa.ViewCount,
  qa.AnswerCount,
  qa.FavoriteCount,
  ta.PostId AS TopTagPostId,
  ta.Title,
  ta.upvotes,
  ta.downvotes,
  ta.comments AS post_comments,
  ta.tag_rank,
  dp.DuplicateOf,
  COALESCE(dp.OwnerUserId, 0) AS owner_user_id,
  (SELECT STRING_AGG(t2.TagName, ', ')
   FROM Tags t2
   WHERE POSITION('<' || t2.TagName || '>' IN ta.Tags) > 0
  ) AS combined_tags
FROM user_points up
JOIN (
    SELECT ta_inner.*
    FROM tag_activity ta_inner
    WHERE ta_inner.tag_rank = 1
) ta ON 1=1
LEFT JOIN duplicate_pairs dp ON dp.PostId = up.UserId
LEFT JOIN user_badge_activity ub ON ub.UserId = up.UserId
LEFT JOIN question_engagement qa ON qa.QuestionId = up.UserId
WHERE
  up.Reputation > 1000
  AND (ta.upvotes > 10 OR ta.downvotes < 5)
  AND (ub.LastBadgeDate IS NULL 
       OR ub.LastBadgeDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
ORDER BY up.Reputation DESC, ta.upvotes DESC
LIMIT 1000;