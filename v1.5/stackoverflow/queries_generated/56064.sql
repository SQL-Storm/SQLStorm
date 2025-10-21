-- {"query": "56064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 348} 

WITH top_100_users AS (
    SELECT Id, Reputation, DisplayName, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS row_num
    FROM Users
),
top_100_posts AS (
    SELECT Id, Score, ViewCount, Title, ROW_NUMBER() OVER (ORDER BY Score DESC) AS row_num
    FROM Posts
    WHERE PostTypeId = 1 AND AnswerCount > 0
),
post_history_data AS (
    SELECT PostId, COUNT(*) AS edit_count, MAX(CreationDate) AS last_edit_date
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
),
vote_data AS (
    SELECT PostId, COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS upvotes, 
           COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS downvotes
    FROM Votes
    GROUP BY PostId
)
SELECT 
    p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
    ph.edit_count, ph.last_edit_date, 
    v.upvotes, v.downvotes, 
    u.DisplayName AS top_user, u.Reputation AS top_user_reputation
FROM Posts p
JOIN post_history_data ph ON p.Id = ph.PostId
JOIN vote_data v ON p.Id = v.PostId
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.Id IN (SELECT Id FROM top_100_posts WHERE row_num <= 100)
AND u.Id IN (SELECT Id FROM top_100_users WHERE row_num <= 100)
ORDER BY p.Score DESC, p.ViewCount DESC;
