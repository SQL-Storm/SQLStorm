WITH TopTags AS (
    SELECT
        CAST(nt.Tag AS varchar) AS Tag,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            unnest(string_to_array(substr(Posts.Tags, 2, length(Posts.Tags) - 2), '><')) AS Tag
        FROM Posts
        WHERE Posts.PostTypeId = 1
    ) nt
    GROUP BY nt.Tag
),
TagScores AS (
    SELECT
        Tag,
        TagCount,
        RANK() OVER (ORDER BY TagCount DESC) AS TagRank
    FROM TopTags
),
UserTopTags AS (
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
    JOIN TagScores tt ON POSITION(tt.Tag IN p.Tags) > 0
    WHERE tt.TagRank <= 10
),
TagBenchmark AS (
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