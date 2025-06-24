
WITH TagStatistics AS (
    SELECT 
        LTRIM(RTRIM(tag)) AS TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END) AS TotalViews,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        AVG(p.Score) AS AverageScore
    FROM 
        Posts p
    JOIN 
        (SELECT 
             value AS tag,
             Id 
         FROM 
             Posts 
         CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><')) AS s
         WHERE 
             PostTypeId = 1) AS tags ON p.Id = tags.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL '1 year' 
    GROUP BY 
        LTRIM(RTRIM(tag))
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        CommentCount,
        TotalViews,
        TotalUpvotes,
        TotalDownvotes,
        AverageScore,
        RANK() OVER (ORDER BY PostCount DESC) AS RankByPosts,
        RANK() OVER (ORDER BY AverageScore DESC) AS RankByScore
    FROM 
        TagStatistics
)
SELECT 
    TT.TagName,
    TT.PostCount,
    TT.CommentCount,
    TT.TotalViews,
    TT.TotalUpvotes,
    TT.TotalDownvotes,
    TT.AverageScore,
    CASE 
        WHEN RankByPosts <= 10 THEN 'Top 10 by Posts'
        WHEN RankByScore <= 10 THEN 'Top 10 by Score'
        ELSE 'Other'
    END AS TagCategory
FROM 
    TopTags TT
ORDER BY 
    TT.PostCount DESC, TT.AverageScore DESC;
