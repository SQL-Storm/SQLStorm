-- {"query": "98.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 842} 
WITH top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
),
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
question_review AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.LastActivityDate,
    q.PostTypeId,
    p.Reputation AS OwnerReputation,
    bud.Name AS BadgeName,
    vh.VoteCount AS UpvotesOnQuestion
  FROM recent_questions q
  LEFT JOIN Users p ON q.OwnerUserId = p.Id
  LEFT JOIN Badges bud ON bud.UserId = q.OwnerUserId
    AND bud.Class = 1 -- Gold badge as signal
  LEFT JOIN (
      SELECT PostId, COUNT(*) AS VoteCount
      FROM Votes
      WHERE VoteTypeId = 2 -- UpMod
      GROUP BY PostId
  ) vh ON vh.PostId = q.PostId
),
complex_metrics AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.Tags,
    tq.OwnerUserId,
    tq.CreationDate,
    tq.ViewCount,
    tq.Score,
    tq.CommentCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.LastActivityDate,
    tq.OwnerReputation,
    tq.BadgeName,
    tq.UpvotesOnQuestion,
    -- Correlated subquery: number of comments by owner on their questions
    (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.UserId = tq.OwnerUserId
        AND c.PostId = tq.PostId
    ) AS OwnerCommentCount,
    -- Window function: rank questions by popularity within last 180 days per tag
    ROW_NUMBER() OVER (PARTITION BY UNNEST(string_to_array(tq.Tags, '><')) ORDER BY tq.ViewCount DESC, tq.Score DESC) AS tag_rank
  FROM question_review tq
  ORDER BY tq.LastActivityDate DESC
)
SELECT
  cq.PostId,
  cq.Title,
  cq.Tags,
  cq.OwnerUserId,
  cq.CreationDate,
  cq.ViewCount,
  cq.Score,
  cq.CommentCount,
  cq.AnswerCount,
  cq.FavoriteCount,
  cq.LastActivityDate,
  cq.OwnerReputation,
  cq.BadgeName,
  cq.UpvotesOnQuestion,
  cq.OwnerCommentCount,
  cq.tag_rank,
  u.Id AS UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation AS UserReputation,
  u.Location AS UserLocation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccessDate,
  u.Views AS UserViews,
  u.UpVotes AS UserUpVotes,
  u.DownVotes AS UserDownVotes
FROM complex_metrics cq
JOIN Users u ON cq.OwnerUserId = u.Id
WHERE
  cq.tag_rank <= 5
  AND cq.OwnerReputation IS NOT NULL
  AND cq.OwnerCommentCount >= 0
ORDER BY cq.LastActivityDate DESC, cq.ViewCount DESC
LIMIT 100;