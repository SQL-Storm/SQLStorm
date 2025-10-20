-- {"query": "28038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1533} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) / NULLIF(COUNT(DISTINCT p.Id), 0) AS AvgAnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2, 3)
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id
    HAVING COUNT(DISTINCT p.Id) > 10 AND AVG(p.Score) > 5
),
BadgeRankings AS (
    SELECT 
        UserId,
        Name,
        Class,
        RANK() OVER (PARTITION BY Class ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges
    GROUP BY UserId, Name, Class
)
SELECT 
    u.Id,
    CONCAT(u.DisplayName, ' (', COALESCE(u.Location, 'Unknown'), ')') AS UserLabel,
    u.Reputation,
    EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
    (ua.PostCount * 3 + ua.CommentCount * 2 + ua.VoteCount + ua.BadgeCount * 5) AS ActivityScore,
    (SELECT MAX(LastEditDate) FROM Posts WHERE OwnerUserId = u.Id) AS LastEdit,
    (SELECT STRING_AGG(TagName, ', ' ORDER BY Count DESC) FROM Tags WHERE Id IN (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><'), NULL) 
        FROM Posts 
        WHERE OwnerUserId = u.Id AND PostTypeId = 1
    )) AS TopTags,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
            AND ph.PostHistoryTypeId = 10
        ) THEN 'Closer' 
        ELSE 'Non-Closer' 
    END AS CloserStatus,
    ROUND(ua.AvgAnswerCount, 2) AS AvgAnswers,
    (SELECT COUNT(*) FROM BadgeRankings br WHERE br.UserId = u.Id AND br.BadgeRank <= 3) AS Top3Badges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    NTILE(4) OVER (ORDER BY u.Reputation) AS ReputationQuartile,
    COALESCE(p.ContentLicense, c.ContentLicense, 'None') AS MainLicense
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN Posts p ON p.Id = (SELECT Id FROM Posts WHERE OwnerUserId = u.Id ORDER BY Score DESC LIMIT 1)
LEFT JOIN Comments c ON c.Id = (SELECT Id FROM Comments WHERE UserId = u.Id ORDER BY Score DESC LIMIT 1)
WHERE u.Reputation > 1000
    AND (u.LastAccessDate - u.CreationDate) > INTERVAL '5 years'
    AND (u.DownVotes < u.UpVotes * 0.1 OR u.DownVotes IS NULL)
ORDER BY ActivityScore DESC, GlobalRank
LIMIT 100;
