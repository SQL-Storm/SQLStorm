
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
),
TagsAnalysis AS (
    SELECT 
        value AS Tag,
        COUNT(*) AS TagCount
    FROM 
        RankedPosts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><') 
    GROUP BY 
        value
    ORDER BY 
        TagCount DESC
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
),
UserActivity AS (
    SELECT 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        SUM(p.ViewCount) AS TotalViews,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 0 
)
SELECT 
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.TotalViews,
    ua.UpVotesReceived,
    ta.Tag AS PopularTag,
    ta.TagCount
FROM 
    UserActivity ua
JOIN 
    TagsAnalysis ta ON ua.ActivityRank <= 5
ORDER BY 
    ua.QuestionsAsked DESC, 
    ua.TotalViews DESC;
