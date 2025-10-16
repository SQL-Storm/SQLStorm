WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
top_posts AS (
    SELECT id, PostTypeId, OwnerUserId, CreationDate, Score, ViewCount
    FROM cte
    WHERE rn = 1
),
user_rep AS (
    SELECT u.Id, u.Reputation,
           CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS user_age
    FROM Users u
)
SELECT
    t.PostTypeId,
    t.OwnerUserId,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    u.Reputation,
    u.user_age,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS post_status,
    COALESCE(
      CAST(EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400 AS INTEGER),
      CAST(EXTRACT(EPOCH FROM (p.CommunityOwnedDate - p.CreationDate)) / 86400 AS INTEGER),
      CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER)
    ) AS post_age,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id)
        ELSE 0
    END AS answer_count,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT COALESCE((SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId), 0))
        ELSE 0
    END AS accepted_answer_score,
    REPLACE(REPLACE(p.Tags, '<', ''), '>', '') AS tags,
    CASE
        WHEN p.PostTypeId = 1 THEN p.Title
        ELSE NULL
    END AS title,
    CASE
        WHEN p.PostTypeId = 1 THEN p.Body
        WHEN p.PostTypeId = 2 THEN (SELECT Body FROM Posts WHERE Id = p.ParentId)
        ELSE NULL
    END AS post_body,
    CASE
        WHEN p.PostTypeId = 1 THEN p.CommentCount
        WHEN p.PostTypeId = 2 THEN (SELECT CommentCount FROM Posts WHERE Id = p.ParentId)
        ELSE 0
    END AS comment_count,
    CASE
        WHEN p.PostTypeId = 1 THEN p.FavoriteCount
        ELSE 0
    END AS favorite_count
FROM top_posts t
JOIN Posts p ON t.Id = p.Id
JOIN user_rep u ON t.OwnerUserId = u.Id
GROUP BY
    t.PostTypeId,
    t.OwnerUserId,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    u.Reputation,
    u.user_age,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.CreationDate,
    p.AcceptedAnswerId,
    p.Id,
    p.Tags,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount
ORDER BY t.Score DESC, t.ViewCount DESC
LIMIT 100;