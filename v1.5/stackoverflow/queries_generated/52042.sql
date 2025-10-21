-- {"query": "52042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 315} 

SELECT 
    tag, 
    AVG(u.Reputation) AS avg_user_reputation, 
    COUNT(DISTINCT pt.Id) AS question_count, 
    COUNT(DISTINCT b.Id) AS total_badges, 
    COUNT(DISTINCT v.Id) AS total_votes_on_questions, 
    AVG(p.Score) AS avg_question_score, 
    COUNT(DISTINCT ph.Id) AS total_history_events
FROM (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag, 
        p.Id, 
        p.OwnerUserId, 
        p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL 
      AND p.ClosedDate IS NULL
) pt
JOIN Users u ON pt.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Only gold badges
LEFT JOIN Votes v ON pt.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- Upvotes and downvotes
LEFT JOIN PostHistory ph ON pt.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits to title, body, tags
GROUP BY tag
HAVING COUNT(DISTINCT pt.Id) > 20
ORDER BY avg_user_reputation DESC, total_badges DESC
LIMIT 15
