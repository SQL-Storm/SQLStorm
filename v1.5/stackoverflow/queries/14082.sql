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
           (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate) AS user_age
    FROM Users u
)
SELECT
    t.PostTypeId,
    t.OwnerUserId,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    u.Reputation,
    EXTRACT(EPOCH FROM u.user_age) / 86400 AS user_age_days,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS post_status,
    COALESCE(DATE_PART('day', p.ClosedDate - p.CreationDate),
             DATE_PART('day', p.CommunityOwnedDate - p.CreationDate),
             DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) AS post_age,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id)
        ELSE 0
    END AS answer_count,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
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
ORDER BY t.Score DESC, t.ViewCount DESC
LIMIT 100;