-- {"query": "33083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 349} 
WITH TopTags AS (
    SELECT
        unnest(string_to_array(substring(Posts.Tags, 2, length(Posts.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts
    WHERE Posts.PostTypeId = 1  -- Questions
    GROUP BY Tag
), TagScores AS (
    SELECT
        Tag,
        TagCount,
        RANK() OVER (ORDER BY TagCount DESC) AS TagRank
    FROM TopTags
), UserTopTags AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        tt.Tag,
        tt.TagCount,
        tt.TagRank,
        p.CreationDate AS QuestionCreationDate,
        p.Id AS QuestionId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.Title
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN TagScores tt ON POSITION(tt.Tag IN p.Tags) > 0  -- Match tags in question's tags
    WHERE tt.TagRank <= 10  -- Top 10 tags for each user
), TagBenchmark AS (
    SELECT
        Tag,
        COUNT(DISTINCT UserId) AS UsersPerTag,
        AVG(QuestionScore) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgViewCount
    FROM UserTopTags
    GROUP BY Tag
)
SELECT
    tb.Tag,
    tb.UsersPerTag,
    tb.AvgQuestionScore,
    tb.AvgViewCount
FROM TagBenchmark tb
ORDER BY tb.UsersPerTag DESC, tb.AvgQuestionScore DESC, tb.AvgViewCount DESC;