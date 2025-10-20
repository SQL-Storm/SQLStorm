WITH RankedPosts AS (
  SELECT 
    p.Id, p.PostTypeId, p.ParentId,
    p.OwnerUserId, u.DisplayName AS OwnerDisplayName, p.CreationDate,
    p.Score, p.ViewCount, p.FavoriteCount,
    p.Title, p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score,
    COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS user_post_count
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
AcceptedAnswerAncestors AS (
  SELECT
    q.Id AS QuestionId,
    a.Id AS AcceptedAnswerId,
    a.OwnerUserId AS AcceptedAnswerOwnerUserId,
    COALESCE(answerer_badges.count_bronze, 0) AS bronze_badges_answerer
  FROM Posts q
  JOIN Posts a ON q.AcceptedAnswerId = a.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS count_bronze
    FROM Badges
    WHERE Class = 3
    GROUP BY UserId
  ) answerer_badges ON a.OwnerUserId = answerer_badges.UserId
  WHERE q.PostTypeId = 1
)
SELECT
  r.Id,
  r.PostTypeId,
  r.ParentId,
  r.OwnerUserId,
  r.OwnerDisplayName,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.FavoriteCount,
  r.Title,
  r.Tags,
  r.rn_score,
  r.user_post_count,
  a.QuestionId,
  a.AcceptedAnswerId,
  a.AcceptedAnswerOwnerUserId,
  a.bronze_badges_answerer
FROM RankedPosts r
LEFT JOIN AcceptedAnswerAncestors a
  ON r.Id = a.AcceptedAnswerId
WHERE 1 = 1;