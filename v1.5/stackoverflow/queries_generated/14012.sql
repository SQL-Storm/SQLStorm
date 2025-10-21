-- {"query": "14012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 591}
WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Tags, 
           CAST(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS VARCHAR(4000)) AS tag_array,
           u.Id AS user_id, u.Reputation, u.CreationDate AS user_creation_date, u.UpVotes, u.DownVotes, u.Views
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
),
top_posts AS (
    SELECT Id, PostTypeId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount, 
           tag_array, user_id, Reputation, user_creation_date, UpVotes, DownVotes, Views
    FROM cte
    WHERE PostTypeId = 1 
    ORDER BY Score DESC
    LIMIT 1000
),
user_badges AS (
    SELECT b.UserId, COUNT(*) AS num_badges, SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges, 
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT top_posts.Id, top_posts.PostTypeId, top_posts.CreationDate, top_posts.Score, top_posts.ViewCount, top_posts.AnswerCount, top_posts.CommentCount, top_posts.FavoriteCount, 
       top_posts.tag_array, top_posts.user_id, top_posts.Reputation, top_posts.user_creation_date, top_posts.UpVotes, top_posts.DownVotes, top_posts.Views,
       user_badges.num_badges, user_badges.gold_badges, user_badges.silver_badges, user_badges.bronze_badges
FROM top_posts
LEFT JOIN user_badges ON top_posts.user_id = user_badges.UserId
ORDER BY top_posts.Score DESC;
