-- {"query": "81.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 305} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
    WHERE Reputation > 1000
),
top_badges AS (
    SELECT b.UserId, b.Name, b.Class,
           CASE
               WHEN Class = 1 THEN 'Gold'
               WHEN Class = 2 THEN 'Silver'
               ELSE 'Bronze'
           END AS BadgeClass
    FROM Badges b
    WHERE b.Date >= '2021-01-01 00:00:00'
),
post_count AS (
    SELECT pu.Id, COUNT(p.Id) AS num_posts
    FROM Posts p
    JOIN Users pu ON p.OwnerUserId = pu.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY pu.Id
),
accepted_answers AS (
    SELECT pu.Id, COUNT(p.AcceptedAnswerId) AS num_accepted_answers
    FROM Posts p
    JOIN Users pu ON p.OwnerUserId = pu.Id
    WHERE p.PostTypeId = 1
    GROUP BY pu.Id
)
SELECT ru.rank, ru.DisplayName, ru.Reputation,
       tb.Name AS TopBadgeName, tb.BadgeClass AS TopBadgeClass,
       pc.num_posts, aa.num_accepted_answers
FROM ranked_users ru
JOIN top_badges tb ON ru.Id = tb.UserId
JOIN post_count pc ON ru.Id = pc.Id
JOIN accepted_answers aa ON ru.Id = aa.Id
ORDER BY ru.rank;