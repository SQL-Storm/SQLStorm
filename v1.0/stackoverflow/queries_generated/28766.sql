WITH TagStatistics AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore,
        AVG(u.Reputation) AS AverageUserReputation
    FROM 
        Tags t
    LEFT JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  -- Filter for questions only
    GROUP BY 
        t.TagName
), 

TopTags AS (
    SELECT 
        TagName,
        PostCount,
        TotalViews,
        TotalScore,
        AverageUserReputation,
        RANK() OVER (ORDER BY PostCount DESC, TotalViews DESC, TotalScore DESC) AS TagRank
    FROM 
        TagStatistics
),

MostActiveUsers AS (
    SELECT
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAnswered,
        SUM(p.ViewCount) AS TotalViewsOnAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived -- Count only Upvotes
    FROM
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 2 -- Count Answers only
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2) -- Upvotes
    GROUP BY 
        u.DisplayName
    ORDER BY 
        QuestionsAnswered DESC
    LIMIT 10 -- Get top 10 users
)

SELECT 
    t.TagName,
    t.PostCount,
    t.TotalViews,
    t.TotalScore,
    t.AverageUserReputation,
    au.DisplayName AS MostActiveUser,
    au.QuestionsAnswered,
    au.TotalViewsOnAnswers,
    au.UpvotesReceived
FROM 
    TopTags t
JOIN 
    MostActiveUsers au ON t.TagRank = 1 -- Join with the Most Active User for the most popular tag
WHERE 
    t.PostCount > 0 -- Only consider tags with posts
ORDER BY 
    t.TagRank;
