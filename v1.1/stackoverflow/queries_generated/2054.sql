-- {"query": "2054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 497} 

WITH RecentBadges AS (
    SELECT UserId, Name, Date
    FROM Badges
    WHERE Date > CURRENT_DATE - INTERVAL '1 year'
),
HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > (
        SELECT AVG(Reputation) FROM Users
    )
),
TopQuestions AS (
    SELECT p.Id, p.Title, p.Score, ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0
),
TopComments AS (
    SELECT c.Id, c.PostId, c.Score, c.Text, c.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC) AS rn
    FROM Comments c
),
ActivePosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.ViewCount, p.AnswerCount, p.ClosedDate,
           COALESCE(p.AnswerCount, 0) - COALESCE(p.CommentCount, 0) AS InteractionRatio,
           p.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned
    FROM Posts p
    WHERE p.LastActivityDate > CURRENT_DATE - INTERVAL '30 days'
),
LinkedPosts AS (
    SELECT DISTINCT pl.PostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
)
SELECT u.DisplayName, 
       b.Name AS BadgeName,
       q.Title AS QuestionTitle,
       a.InteractionRatio,
       COALESCE(tc.Text, 'No top comment') AS TopComment,
       CASE 
           WHEN ap.IsCommunityOwned THEN 'Community'
           ELSE 'Individual'
       END AS OwnershipType
FROM RecentBadges b
JOIN HighReputationUsers u ON b.UserId = u.Id
LEFT JOIN TopQuestions q ON q.OwnerUserId = u.Id AND q.rn = 1
LEFT JOIN ActivePosts a ON q.Id = a.Id
LEFT JOIN TopComments tc ON tc.PostId = a.Id AND tc.rn = 1
LEFT JOIN LinkedPosts lp ON a.Id = lp.PostId
WHERE a.ClosedDate IS NULL OR a.ClosedDate > a.CreationDate + INTERVAL '1 day'
ORDER BY u.Reputation DESC, a.InteractionRatio DESC;
