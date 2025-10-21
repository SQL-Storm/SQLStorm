WITH ranked_badges AS (
    SELECT Id,
           UserId,
           Name,
           Date,
           Class,
           TagBased,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
    FROM Badges
),
active_users AS (
    SELECT Id,
           DisplayName,
           CreationDate
    FROM Users
    WHERE LastAccessDate >= TIMESTAMP '2021-01-01 00:00:00'
),
top_user_badges AS (
    SELECT rb.Id,
           rb.UserId,
           rb.Name,
           rb.Date,
           rb.Class,
           rb.TagBased
    FROM ranked_badges rb
    JOIN active_users au ON rb.UserId = au.Id
    WHERE rb.rn <= 3
),
top_user_posts AS (
    SELECT p.Id,
           p.Title,
           p.OwnerUserId,
           p.Score,
           p.CreationDate
    FROM Posts p
    JOIN active_users au ON p.OwnerUserId = au.Id
    WHERE p.PostTypeId = 1
),
user_interactions AS (
    SELECT tu.Id AS UserId,
           SUM(tup.Score) AS total_score,
           COUNT(tup.Id) AS total_posts
    FROM top_user_posts tup
    JOIN active_users tu ON tup.OwnerUserId = tu.Id
    GROUP BY tu.Id
)
SELECT au.DisplayName,
       au.CreationDate,
       tub.Name AS BadgeName,
       tub.Date AS BadgeDate,
       tub.Class AS BadgeClass,
       tub.TagBased AS TagBadge,
       ui.total_score,
       ui.total_posts
FROM top_user_badges tub
JOIN active_users au ON tub.UserId = au.Id
JOIN user_interactions ui ON au.Id = ui.UserId
ORDER BY ui.total_score DESC,
         ui.total_posts DESC;