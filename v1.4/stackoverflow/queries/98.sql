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
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
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
    -- Use CROSS JOIN LATERAL to explode tags if necessary, otherwise compute rank per tag using unnest result
    ROW_NUMBER() OVER (
      PARTITION BY tag_value
      ORDER BY tq.ViewCount DESC, tq.Score DESC
    ) AS tag_rank
  FROM question_review tq
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(tq.Tags, '><')) AS tag_value
  ) AS t
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