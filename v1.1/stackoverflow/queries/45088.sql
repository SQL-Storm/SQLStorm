WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (
            SELECT (unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS TagName, Id
            FROM Posts
        ) t ON t.Id = p.Id
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, t.TagName
),
TagPerformanceMetrics AS (
    SELECT 
        TagName,
        AVG(TotalTagScore) AS AvgTagScore,
        SUM(PostCount) AS TotalTagPosts,
        COUNT(DISTINCT UserId) AS UniqueUserCount
    FROM 
        ActiveUserTags
    WHERE 
        TagRank <= 3
    GROUP BY 
        TagName
    HAVING 
        COUNT(DISTINCT UserId) > 10
),
VotesByTag AS (
    SELECT t.TagName, COUNT(*) AS VoteCount
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    JOIN (
        SELECT (unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS TagName, Id
        FROM Posts
    ) t ON t.Id = p.Id
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY t.TagName
),
LinksByTag AS (
    SELECT t.TagName, COUNT(*) AS LinkCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN (
        SELECT (unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS TagName, Id
        FROM Posts
    ) t ON t.Id = p.Id
    GROUP BY t.TagName
)
SELECT 
    t.TagName,
    t.AvgTagScore,
    t.TotalTagPosts,
    t.UniqueUserCount,
    v.VoteCount,
    pl.LinkCount
FROM 
    TagPerformanceMetrics t
JOIN 
    VotesByTag v ON t.TagName = v.TagName
JOIN 
    LinksByTag pl ON t.TagName = pl.TagName
ORDER BY 
    t.AvgTagScore DESC, 
    t.TotalTagPosts DESC
LIMIT 50;