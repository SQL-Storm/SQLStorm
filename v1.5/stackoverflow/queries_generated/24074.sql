-- {"query": "24074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2060} 
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
  GROUP BY u.Id
),
tag_activity AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Tags,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
         COUNT(c.Id) AS comments,
         ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS tag_rank
  FROM Posts p
  CROSS APPLY (SELECT STRING_SPLIT(p.Tags, '>')[0] AS TagName) t
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.Tags, t.TagName
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
         STRING_AGG(b.Name, ', ') WITHIN GROUP (ORDER BY b.Date DESC) AS BadgeNames,
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
  (SELECT STRING_AGG(T.TagName, ', ')
   FROM Tags T
   WHERE T.TagName = ANY (STRING_SPLIT(ta.Tags, '>')))
    AS combined_tags
FROM user_points up
CROSS JOIN LATERAL (
    SELECT *
    FROM tag_activity ta
    WHERE ta.tag_rank = 1
    ORDER BY ta.upvotes DESC
    LIMIT 1
) ta
LEFT JOIN duplicate_pairs dp ON dp.PostId = up.UserId
LEFT JOIN user_badge_activity ub ON ub.UserId = up.UserId
LEFT JOIN question_engagement qa ON qa.QuestionId = up.UserId
WHERE
  up.Reputation > 1000
  AND (ta.upvotes > 10 OR ta.downvotes < 5)
  AND (ub.LastBadgeDate IS NULL 
       OR ub.LastBadgeDate >= CURRENT_TIMESTAMP - INTERVAL '90 days')
ORDER BY up.Reputation DESC, ta.upvotes DESC
LIMIT 1000;