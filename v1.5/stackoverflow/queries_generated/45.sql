-- {"query": "45.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 280} 
WITH user_reputation AS (
    SELECT u.Id, u.DisplayName, u.Reputation, b.Name AS BadgeName, b.Class
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
),
post_vote_statistics AS (
    SELECT p.Id AS PostId, COUNT(v.Id) AS TotalVotes, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
user_post_interaction AS (
    SELECT u.Id AS UserId, p.Id AS PostId, c.CreationDate AS CommentDate
    FROM Users u
    JOIN Comments c ON u.Id = c.UserId
    JOIN Posts p ON c.PostId = p.Id
),
final_query AS (
    SELECT ur.DisplayName, ur.Reputation, pst.TotalVotes, pst.UpVotes, pst.DownVotes, upi.CommentDate
    FROM user_reputation ur
    LEFT JOIN post_vote_statistics pst ON ur.Id = pst.PostId
    LEFT JOIN user_post_interaction upi ON ur.Id = upi.UserId
)
SELECT *
FROM final_query
ORDER BY Reputation DESC, TotalVotes DESC, CommentDate DESC;