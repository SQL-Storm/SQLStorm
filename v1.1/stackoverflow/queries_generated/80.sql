-- {"query": "80.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 311} 
WITH ranked_badges AS (
    SELECT Id, UserId, Name, Date, Class, TagBased,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
    FROM Badges
),
active_users AS (
    SELECT Id, DisplayName, CreationDate
    FROM Users
    WHERE LastAccessDate >= '2021-01-01 00:00:00'
),
top_user_badges AS (
    SELECT rb.Id, rb.UserId, rb.Name, rb.Date, rb.Class, rb.TagBased
    FROM ranked_badges rb
    JOIN active_users au ON rb.UserId = au.Id
    WHERE rn <= 3
),
top_user_posts AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.Score, p.CreationDate
    FROM Posts p
    JOIN active_users au ON p.OwnerUserId = au.Id
    WHERE PostTypeId = 1
),
user_interactions AS (
    SELECT UserId, SUM(Score) AS total_score, COUNT(Id) AS total_posts
    FROM top_user_posts
    GROUP BY UserId
)
SELECT tu.DisplayName, tu.CreationDate, tub.Name AS BadgeName, tub.Date AS BadgeDate,
       tub.Class AS BadgeClass, tub.TagBased AS TagBadge,
       u.total_score, u.total_posts
FROM top_user_badges tub
JOIN active_users tu ON tub.UserId = tu.Id
JOIN user_interactions u ON tub.UserId = u.UserId
ORDER BY u.total_score DESC, u.total_posts DESC;