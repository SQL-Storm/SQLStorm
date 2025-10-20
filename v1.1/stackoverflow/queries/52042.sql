SELECT 
    tag, 
    AVG(u.Reputation) AS avg_user_reputation, 
    COUNT(DISTINCT pt.Id) AS question_count, 
    COUNT(DISTINCT b.Id) AS total_badges, 
    COUNT(DISTINCT v.Id) AS total_votes_on_questions, 
    AVG(pt.Score) AS avg_question_score, 
    COUNT(DISTINCT ph.Id) AS total_history_events
FROM (
    SELECT 
        unnest(string_to_array(substring(Posts.Tags, 2, length(Posts.Tags) - 2), '><')) AS tag, 
        Posts.Id, 
        Posts.OwnerUserId, 
        Posts.Score
    FROM Posts
    WHERE Posts.PostTypeId = 1 
      AND Posts.Tags IS NOT NULL 
      AND Posts.ClosedDate IS NULL
) pt
JOIN Users u ON pt.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
LEFT JOIN Votes v ON pt.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN PostHistory ph ON pt.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
GROUP BY tag
HAVING COUNT(DISTINCT pt.Id) > 20
ORDER BY avg_user_reputation DESC, total_badges DESC
LIMIT 15;