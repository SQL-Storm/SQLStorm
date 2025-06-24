
WITH TagStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(u.Reputation) AS AverageUserReputation
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 100 
    GROUP BY t.TagName
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        TotalViews,
        QuestionCount,
        AnswerCount,
        CommentCount,
        AverageUserReputation,
        @row_number := @row_number + 1 AS Rank
    FROM TagStats, (SELECT @row_number := 0) AS r
    ORDER BY TotalViews DESC
)
SELECT 
    TagName,
    PostCount,
    TotalViews,
    QuestionCount,
    AnswerCount,
    CommentCount,
    AverageUserReputation
FROM TopTags
WHERE Rank <= 10;
