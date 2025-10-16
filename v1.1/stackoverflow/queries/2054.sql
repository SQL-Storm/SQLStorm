WITH RecentBadges AS (
    SELECT UserId, Name, Date
    FROM Badges
    WHERE Date > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
),
HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > (
        SELECT AVG(Reputation) FROM Users
    )
),
TopQuestions AS (
    SELECT p.Id, p.Title, p.Score, p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0
),
TopComments AS (
    SELECT c.Id, c.PostId, c.Score, c.Text, c.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC) AS rn
    FROM Comments c
),
ActivePosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.ViewCount, p.AnswerCount, p.ClosedDate, p.CommentCount, p.CommunityOwnedDate,
           COALESCE(p.AnswerCount, 0) - COALESCE(p.CommentCount, 0) AS InteractionRatio,
           (p.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned
    FROM Posts p
    WHERE p.LastActivityDate > CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
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
           WHEN a.IsCommunityOwned THEN 'Community'
           ELSE 'Individual'
       END AS OwnershipType,
       u.Reputation
FROM RecentBadges b
JOIN HighReputationUsers u ON b.UserId = u.Id
LEFT JOIN TopQuestions q ON q.OwnerUserId = u.Id AND q.rn = 1
LEFT JOIN ActivePosts a ON q.Id = a.Id
LEFT JOIN TopComments tc ON tc.PostId = a.Id AND tc.rn = 1
LEFT JOIN LinkedPosts lp ON a.Id = lp.PostId
WHERE (a.ClosedDate IS NULL OR a.ClosedDate > a.CreationDate + INTERVAL '1 day')
GROUP BY
    u.DisplayName,
    b.Name,
    q.Title,
    a.InteractionRatio,
    tc.Text,
    a.IsCommunityOwned,
    u.Reputation
ORDER BY u.Reputation DESC, a.InteractionRatio DESC;