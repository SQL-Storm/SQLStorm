-- {"query": "33054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 549} 
WITH PostTags AS (
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT
        Tag,
        COUNT(*) AS TagCount
    FROM PostTags
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 50
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
ActivityTrend AS (
    SELECT
        date_trunc('month', p.CreationDate) AS Month,
        COUNT(*) AS PostsCreated
    FROM Posts p
    GROUP BY Month
),
TagPopularity AS (
    SELECT
        Tag,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM PostTags pt
    JOIN Posts p ON pt.PostId = p.Id
    GROUP BY Tag
)
SELECT
    -- Top 50 most used tags
    (SELECT json_agg(t) FROM (
        SELECT Tag, TagCount
        FROM TopTags
    ) t) AS TopTags,
    -- Top user engagement metrics
    (SELECT json_agg(ue) FROM (
        SELECT UserId, DisplayName, QuestionCount, AnswerCount, CommentCount, TotalViews, AverageScore
        FROM UserEngagement
        ORDER BY QuestionCount + AnswerCount DESC
        LIMIT 100
    ) ue) AS TopUsers,
    -- Monthly activity trends
    (SELECT json_agg(at) FROM (
        SELECT Month, PostsCreated
        FROM ActivityTrend
        ORDER BY Month
    ) at) AS MonthlyActivity,
    -- Tag popularity summary
    (SELECT json_agg(tp) FROM (
        SELECT Tag, PostCount, AvgScore, TotalViews
        FROM TagPopularity
        ORDER BY PostCount DESC
        LIMIT 50
    ) tp) AS TagInsights;