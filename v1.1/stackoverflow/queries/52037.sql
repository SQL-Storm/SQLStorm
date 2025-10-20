-- {"query": "52037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 286} 
SELECT u.Id, u.DisplayName, u.Reputation, u.Location, total_upvotes, question_count, AVG(p.Score) AS avg_question_score, COUNT(DISTINCT c.Id) AS total_comments_on_questions, COUNT(DISTINCT ph.Id) AS edit_count
FROM Users u
JOIN (
    SELECT OwnerUserId, SUM(Score) AS total_upvotes, COUNT(*) AS question_count
    FROM Posts
    WHERE PostTypeId = 1 AND ClosedDate IS NULL AND AcceptedAnswerId IS NOT NULL
    GROUP BY OwnerUserId
    ORDER BY total_upvotes DESC
    LIMIT 1000
) top_users ON u.Id = top_users.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.AcceptedAnswerId IS NOT NULL
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
WHERE u.Reputation > 1000 AND u.LastAccessDate > '2020-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, total_upvotes, question_count
HAVING total_upvotes > 100
ORDER BY total_upvotes DESC, u.Reputation DESC
LIMIT 10;