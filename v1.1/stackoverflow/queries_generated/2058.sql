-- {"query": "2058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 510} 

WITH RecentUsers AS (
    SELECT 
        Id AS UserId, 
        DisplayName,
        ROW_NUMBER() OVER (PARTITION BY Location ORDER BY CreationDate DESC) AS rn
    FROM Users
    WHERE Reputation > 1000 AND LastAccessDate > now() - interval '1 year'
),
HighScorePosts AS (
    SELECT 
        Posts.Id AS PostId, 
        Posts.Title, 
        SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END) 
            OVER (PARTITION BY Posts.Id) AS UpVotes,
        SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END) 
            OVER (PARTITION BY Posts.Id) AS DownVotes
    FROM Posts 
    LEFT JOIN Votes ON Posts.Id = Votes.PostId
    WHERE Posts.Score > 10
),
DuplicatePosts AS (
    SELECT 
        Posts.Id AS DuplicatePostId,
        RelatedPostId
    FROM PostLinks
    INNER JOIN Posts ON Posts.Id = PostLinks.PostId
    WHERE LinkTypeId = 3
),
BadgeInfo AS (
    SELECT 
        Users.Id AS UserId, 
        Badges.Name AS BadgeName, 
        MAX(Badges.Date) AS LastBadgeDate
    FROM Badges 
    INNER JOIN Users ON Users.Id = Badges.UserId
    GROUP BY Users.Id, Badges.Name
    HAVING COUNT(*) > 2 AND MAX(Badges.Date) > now() - interval '6 months'
)
SELECT 
    R.UserId, 
    R.DisplayName, 
    COALESCE(H.UpVotes, 0) - COALESCE(H.DownVotes, 0) AS NetVotes,
    H.Title AS PostTitle,
    D.DuplicatePostId,
    STRING_AGG(
        CASE 
            WHEN B.BadgeName IS NOT NULL THEN B.BadgeName 
            ELSE 'No badge' 
        END, ', ') AS Badges
FROM RecentUsers R
LEFT JOIN HighScorePosts H ON R.UserId = H.PostId
LEFT OUTER JOIN DuplicatePosts D ON H.PostId = D.DuplicatePostId
LEFT JOIN BadgeInfo B ON R.UserId = B.UserId
WHERE R.rn <= 5 
GROUP BY R.UserId, R.DisplayName, H.UpVotes, H.DownVotes, H.Title, D.DuplicatePostId
ORDER BY NetVotes DESC, R.DisplayName;
