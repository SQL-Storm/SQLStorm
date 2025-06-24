
WITH PostTagCounts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        COUNT(DISTINCT t.TagName) AS TagCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS IsQuestion,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS IsAnswer
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    CROSS APPLY 
        (SELECT value AS TagName FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><')) AS tag
    LEFT JOIN 
        Tags t ON t.TagName = tag.TagName
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(b.Class, 0)) AS BadgeClassSum
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
AggregatedResults AS (
    SELECT
        pt.PostId,
        pt.Title,
        pt.CreationDate,
        pt.TagCount,
        ur.DisplayName AS UserDisplayName,
        ur.Reputation,
        ur.PostCount,
        ur.BadgeClassSum,
        CASE WHEN pt.IsQuestion > 0 THEN 'Question' ELSE 'Answer' END AS PostType
    FROM 
        PostTagCounts pt
    JOIN 
        UserReputation ur ON ur.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pt.PostId)
)

SELECT 
    PostId,
    Title,
    CreationDate,
    TagCount,
    UserDisplayName,
    Reputation,
    PostCount,
    BadgeClassSum,
    PostType
FROM 
    AggregatedResults
WHERE 
    TagCount > 3
ORDER BY 
    CreationDate DESC, Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
