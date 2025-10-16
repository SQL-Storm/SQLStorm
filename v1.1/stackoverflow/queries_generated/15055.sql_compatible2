WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId, 
        u.DisplayName, 
        COUNT(*) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS AuthorRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 5
    GROUP BY p.OwnerUserId, u.DisplayName
),
TagPopularity AS (
    SELECT 
        Tag,
        COUNT(*) AS TagCount,
        AVG(AnswerCount) AS AvgAnswersPerQuestion
    FROM (
        SELECT
            p.Id,
            p.OwnerUserId,
            p.Score,
            p.Tags,
            p.AnswerCount,
            TRIM(tag) AS Tag
        FROM Posts p,
        LATERAL (
            SELECT value AS tag
            FROM (
                SELECT regexp_split_to_table(
                    substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)),
                    '><'
                ) AS value
            ) s
        ) split
        WHERE p.PostTypeId = 1
    ) t
    GROUP BY Tag
)
SELECT 
    t.DisplayName AS TopAuthor,
    t.QuestionCount,
    t.AvgQuestionScore,
    t.AuthorRank,
    COALESCE(
        (SELECT MAX(tp.AvgAnswersPerQuestion) 
         FROM TagPopularity tp 
         JOIN Posts p ON p.Tags LIKE '%' || tp.Tag || '%'
         WHERE p.OwnerUserId = t.OwnerUserId
        ), 0) AS MaxTagAvgAnswers,
    CASE 
        WHEN t.QuestionCount > 50 THEN 'Prolific'
        WHEN t.QuestionCount > 20 THEN 'Active'
        ELSE 'Occasional'
    END AS AuthorCategory,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = t.OwnerUserId AND v.VoteTypeId IN (2, 3)) AS TotalVotes
FROM TopQuestionAuthors t
WHERE t.AuthorRank <= 100
ORDER BY t.QuestionCount DESC, t.AvgQuestionScore DESC
LIMIT 25;