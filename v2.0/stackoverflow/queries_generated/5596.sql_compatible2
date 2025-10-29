WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_user,
    COUNT(*) OVER () AS total_posts
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TagNames AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count AS TagCount,
    t.WikiPostId,
    t.ExcerptPostId
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
TopComments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserDisplayName,
    c.Text,
    c.CreationDate
  FROM Comments c
  JOIN (
    SELECT PostId, MAX(CreationDate) AS MaxCommentDate
    FROM Comments
    GROUP BY PostId
  ) m ON m.PostId = c.PostId AND m.MaxCommentDate = c.CreationDate
),
PostScores AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.Score,
    COALESCE(p.ViewCount * 2, 0) + COALESCE(p.Score, 0) +
      COALESCE((
        SELECT AVG(v.BountyAmount)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 8
      ), 0) AS activity_score
  FROM Posts p
  WHERE p.PostTypeId = 1
),
HighActivity AS (
  SELECT PostId FROM PostScores WHERE activity_score > 1000
  UNION
  SELECT pc.Id AS PostId
  FROM TopComments tc
  JOIN Posts pc ON pc.Id = tc.PostId
  WHERE tc.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
)
SELECT
  rp.Id AS PostId,
  rp.Title,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate,
  rp.ViewCount,
  rp.Score,
  rp.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.CreationDate AS UserCreationDate,
  COALESCE(u.Reputation, 0) AS ReputationSafe,
  tc.CommentId AS TopCommentId,
  tc.UserDisplayName AS CommentAuthor,
  tc.Text AS CommentText,
  pa.Title AS ParentQuestionTitle,
  ha.TagName AS TagName,
  hact.total_posts
FROM Posts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN TopComments tc ON tc.PostId = rp.Id
LEFT JOIN Posts pa ON rp.ParentId = pa.Id
LEFT JOIN TagNames ha ON rp.Tags LIKE ('%' || '>' || ha.TagName || '<' || '%')
LEFT JOIN RecentActivity hact ON hact.PostId = rp.Id
WHERE rp.PostTypeId = 1
  AND rp.Id IN (SELECT PostId FROM HighActivity)
GROUP BY
  rp.Id,
  rp.Title,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.ViewCount,
  rp.Score,
  rp.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.CreationDate,
  tc.CommentId,
  tc.UserDisplayName,
  tc.Text,
  pa.Title,
  ha.TagName,
  hact.total_posts
ORDER BY rp.LastActivityDate DESC
LIMIT 100;