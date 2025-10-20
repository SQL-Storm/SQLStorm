-- {"query": "26038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 552} 

WITH top_users AS (
    SELECT u.Id, u.DisplayName, SUM(v.BountyAmount) AS total_bounty
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    WHERE v.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName
    ORDER BY total_bounty DESC
    LIMIT 10
),
top_posts AS (
    SELECT p.Id, p.Title, p.Score, COUNT(DISTINCT ph.PostId) AS edit_count
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY p.Id, p.Title, p.Score
    ORDER BY edit_count DESC
    LIMIT 10
),
user_badges AS (
    SELECT u.Id, COUNT(DISTINCT b.Name) AS badge_count
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(tb.total_bounty, 0) AS total_bounty,
    COALESCE(ub.badge_count, 0) AS badge_count,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = u.Id AND c.Score > 0) AS positive_comments,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10) AS close_votes,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS upvotes,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS downvotes,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS questions,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS answers,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) AS linked_posts,
    (SELECT COUNT(*) 
     FROM Tags t 
     WHERE t.TagName IN (SELECT Tags FROM Posts WHERE OwnerUserId = u.Id)) AS tags
FROM Users u
LEFT JOIN top_users tb ON u.Id = tb.Id
LEFT JOIN user_badges ub ON u.Id = ub.Id
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC;
