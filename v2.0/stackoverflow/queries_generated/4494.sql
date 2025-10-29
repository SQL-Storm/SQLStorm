-- {"query": "4494.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1136} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) AS RankByReputationAndPostCount,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AveragePostScore,
        LAG(u.CreationDate, 1, '1970-01-01') OVER (ORDER BY u.CreationDate) AS PreviousUserCreationDate,
        LEAD(u.CreationDate, 1, '9999-12-31') OVER (ORDER BY u.CreationDate) AS NextUserCreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9]%'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT c.Id) AS CommenterCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2, 3)) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE -1 END) AS NetVoteScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
    GROUP BY
        p.Id, p.Title, pt.Name, p.ClosedDate
),
TagSpecificPosts AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScoreForTag,
        SUM(p.AnswerCount) AS TotalAnswersForTag
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY
        t.TagName
)
SELECT
    '---- User Performance Metrics ----' AS Category,
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.PostCount,
    rua.CommentCount,
    rua.AveragePostScore,
    CASE
        WHEN DATEDIFF(day, rua.PreviousUserCreationDate, rua.CreationDate) < 7 THEN 'New User'
        WHEN DATEDIFF(day, rua.NextUserCreationDate, GETDATE()) < 7 THEN 'Very Recent User'
        ELSE 'Established User'
    END AS UserTenureStatus,
    rua.BadgeCount,
    CASE WHEN rua.BadgeCount > 50 THEN 'Highly Decorated' ELSE 'Standard' END AS UserDecorationLevel
FROM
    RankedUserActivity rua
WHERE
    rua.RankByReputationAndPostCount BETWEEN 1 AND 100
UNION ALL
SELECT
    '---- Post Engagement Metrics ----' AS Category,
    NULL AS UserId,
    pe.Title AS DisplayName,
    pe.VoteCount AS Reputation,
    pe.UpVotes AS PostCount,
    pe.CommenterCount AS CommentCount,
    pe.NetVoteScore AS AveragePostScore,
    pe.PostTypeName AS UserTenureStatus,
    NULL AS BadgeCount,
    pe.PostStatus AS UserDecorationLevel
FROM
    PostEngagement pe
WHERE
    pe.VoteCount > 1000
UNION ALL
SELECT
    '---- Tag Performance Metrics ----' AS Category,
    NULL AS UserId,
    tsp.TagName AS DisplayName,
    tsp.AvgScoreForTag AS Reputation,
    tsp.PostsWithTag AS PostCount,
    tsp.TotalAnswersForTag AS CommentCount,
    NULL AS AveragePostScore,
    NULL AS UserTenureStatus,
    NULL AS BadgeCount,
    NULL AS UserDecorationLevel
FROM
    TagSpecificPosts tsp
WHERE
    tsp.PostsWithTag > 5000
ORDER BY
    Category, Reputation DESC;
