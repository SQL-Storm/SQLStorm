-- {"query": "15.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 194} 
WITH post_scores AS (
    SELECT p.Id, p.Score,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.Score
),
post_activity AS (
    SELECT p.Id, p.LastActivityDate, COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id, p.LastActivityDate
)
SELECT ps.Id, ps.Score, ps.UpVotes, ps.DownVotes,
       pa.LastActivityDate, pa.CommentCount
FROM post_scores ps
JOIN post_activity pa ON ps.Id = pa.Id
ORDER BY ps.Score DESC, pa.LastActivityDate ASC;