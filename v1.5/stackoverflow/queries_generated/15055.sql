-- {"query": "15055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 130760, "output_tokens": 38562} 
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
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(AnswerCount) AS AvgAnswersPerQuestion
    FROM Posts
    WHERE PostTypeId = 1
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