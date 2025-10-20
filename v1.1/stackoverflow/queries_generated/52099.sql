-- {"query": "52099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 551} 
SELECT u.Id, u.DisplayName, u.Reputation,
       q_stats.total_questions, q_stats.avg_question_score,
       a_stats.total_answers, a_stats.accepted_answers,
       v_stats.total_upvotes_received,
       b_stats.gold_badges, b_stats.silver_badges, b_stats.bronze_badges,
       c_stats.comment_count
FROM Users u
LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS total_questions, AVG(Score) AS avg_question_score
           FROM Posts
           WHERE PostTypeId = 1
           GROUP BY OwnerUserId) q_stats ON u.Id = q_stats.OwnerUserId
LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS total_answers, SUM(CASE WHEN Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS accepted_answers
           FROM Posts
           WHERE PostTypeId = 2
           GROUP BY OwnerUserId) a_stats ON u.Id = a_stats.OwnerUserId
LEFT JOIN (SELECT p.OwnerUserId, SUM(v_up.UpCount) AS total_upvotes_received
           FROM Posts p
           LEFT JOIN (SELECT PostId, COUNT(*) AS UpCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v_up ON p.Id = v_up.PostId
           GROUP BY p.OwnerUserId) v_stats ON u.Id = v_stats.OwnerUserId
LEFT JOIN (SELECT UserId, SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
                   SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
                   SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
           FROM Badges
           GROUP BY UserId) b_stats ON u.Id = b_stats.UserId
LEFT JOIN (SELECT UserId, COUNT(*) AS comment_count
           FROM Comments
           GROUP BY UserId) c_stats ON u.Id = c_stats.UserId
WHERE u.Reputation > 1000
  AND q_stats.total_questions IS NOT NULL
  AND a_stats.total_answers IS NOT NULL
  AND v_stats.total_upvotes_received IS NOT NULL
ORDER BY (q_stats.total_questions * q_stats.avg_question_score + a_stats.total_answers + a_stats.accepted_answers * 2 + v_stats.total_upvotes_received * 0.1 + b_stats.gold_badges * 100 + b_stats.silver_badges * 50 + b_stats.bronze_badges * 25 + c_stats.comment_count * 0.01) DESC
LIMIT 100;