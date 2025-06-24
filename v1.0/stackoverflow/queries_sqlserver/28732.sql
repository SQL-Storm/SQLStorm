
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  
        AND p.LastActivityDate >= '2024-10-01 12:34:56' - INTERVAL '1 year'  
),
PostScoreStats AS (
    SELECT 
        pr.OwnerUserId,
        COUNT(DISTINCT pr.PostId) AS TotalQuestions,
        AVG(pr.ViewCount) AS AvgViewCount,
        SUM(CASE WHEN pr.Rank = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersCount  
    FROM 
        RankedPosts pr
    GROUP BY 
        pr.OwnerUserId
),
PopularTags AS (
    SELECT 
        value AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts p
    CROSS APPLY STRING_SPLIT(p.Tags, '><') 
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        value
    ORDER BY 
        TagCount DESC
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ps.TotalQuestions,
    ps.AvgViewCount,
    ps.AcceptedAnswersCount,
    STRING_AGG(DISTINCT pt.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    PostScoreStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN 
    PopularTags pt ON pt.TagName IN (
        SELECT value
        FROM STRING_SPLIT((SELECT STRING_AGG(p.Tags, '><') FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), '><')
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, ps.TotalQuestions, ps.AvgViewCount, ps.AcceptedAnswersCount
ORDER BY 
    ps.TotalQuestions DESC,
    u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
