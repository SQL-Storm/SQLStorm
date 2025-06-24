WITH TagStats AS (
    SELECT 
        Tags.TagName,
        COUNT(DISTINCT Posts.Id) AS PostCount,
        SUM(COALESCE(Posts.ViewCount, 0)) AS TotalViews,
        SUM(COALESCE(Votes.VoteTypeId = 2, 0)::int) AS TotalUpvotes,
        SUM(COALESCE(Votes.VoteTypeId = 3, 0)::int) AS TotalDownvotes,
        SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        STRING_AGG(DISTINCT Users.DisplayName, ', ') AS ActiveUsers
    FROM 
        Tags 
    JOIN 
        Posts ON Posts.Tags LIKE '%' || Tags.TagName || '%'
    LEFT JOIN 
        Votes ON Votes.PostId = Posts.Id
    LEFT JOIN 
        Users ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Tags.TagName
),
TagPerformance AS (
    SELECT 
        TagName,
        PostCount,
        TotalViews,
        TotalUpvotes,
        TotalDownvotes,
        QuestionCount,
        AnswerCount,
        (TotalUpvotes - TotalDownvotes) AS NetVotes,
        CASE 
            WHEN PostCount > 0 THEN (TotalViews::decimal / PostCount) ELSE 0 
        END AS AverageViewsPerPost,
        CASE 
            WHEN QuestionCount > 0 THEN (TotalUpvotes::decimal / QuestionCount) ELSE 0 
        END AS AverageUpvotesPerQuestion,
        CASE 
            WHEN AnswerCount > 0 THEN (TotalUpvotes::decimal / AnswerCount) ELSE 0 
        END AS AverageUpvotesPerAnswer,
        ActiveUsers
    FROM 
        TagStats
)
SELECT 
    TagName,
    PostCount,
    TotalViews,
    TotalUpvotes,
    TotalDownvotes,
    NetVotes,
    AverageViewsPerPost,
    AverageUpvotesPerQuestion,
    AverageUpvotesPerAnswer,
    ActiveUsers
FROM 
    TagPerformance
ORDER BY 
    NetVotes DESC, TotalViews DESC
LIMIT 10;
