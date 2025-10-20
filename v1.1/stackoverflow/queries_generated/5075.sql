-- {"query": "5075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 994} 
WITH active_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS NumPosts,
        COUNT(DISTINCT b.Id) AS NumBadges,
        COALESCE(SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END),0) AS NumAnswers,
        COALESCE(SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END),0) AS NumQuestions,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE
        u.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
question_stats AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        LENGTH(q.Body) AS BodyLength,
        COALESCE((
            SELECT MAX(a.Score)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2
        ),0) AS MaxAnswerScore,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = q.Id AND c.Score > 0
        ) AS NumHelpfulComments
    FROM
        Posts q
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate > NOW() - INTERVAL '1 year'
),
answerers_with_high_score AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(*) AS NumHighScoreAnswers
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
        AND a.Score >= 10
    GROUP BY a.OwnerUserId
)
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.NumPosts,
    au.NumAnswers,
    au.NumQuestions,
    au.NumBadges,
    au.ReputationRank,
    COUNT(DISTINCT qs.QuestionId) AS RecentQuestions,
    AVG(qs.QuestionScore) AS AvgQuestionScore,
    SUM(CASE WHEN qs.MaxAnswerScore > 0 THEN 1 ELSE 0 END) AS QuestionsWithGoodAnswers,
    MAX(qs.ViewCount) AS MaxViewsOnAQuestion,
    MIN(qs.BodyLength) AS MinQuestionBodyLength,
    AVG(CASE WHEN qs.NumHelpfulComments IS NULL OR qs.NumHelpfulComments = 0 THEN NULL ELSE qs.NumHelpfulComments END) AS AvgHelpfulCommentsPerQuestion,
    COALESCE(aha.NumHighScoreAnswers, 0) AS NumHighScoreAnswers,
    (
        SELECT array_to_string(array_agg(t.TagName ORDER BY t.Count DESC), ', ')
        FROM (
            SELECT DISTINCT
                unnest(string_to_array(
                    substring(qs2.Tags, 2, length(qs2.Tags)-2),
                    '><'
                )) AS TagName
            FROM Posts qs2
            WHERE qs2.OwnerUserId = au.UserId
              AND qs2.PostTypeId = 1
              AND qs2.Tags IS NOT NULL
        ) AS tags
        JOIN Tags t ON t.TagName = tags.TagName
    ) AS TopTags,
    CASE
        WHEN SUM(CASE WHEN qs.QuestionScore < 0 THEN 1 ELSE 0 END) > 3 THEN 'Warning: Many downvoted questions'
        WHEN AVG(qs.QuestionScore) > 7 THEN 'Great question quality'
        ELSE 'Average'
    END AS QuestionQuality
FROM
    active_users au
    LEFT JOIN question_stats qs ON qs.OwnerUserId = au.UserId
    LEFT JOIN answerers_with_high_score aha ON aha.UserId = au.UserId
WHERE
    au.NumPosts > 5
    AND (
        qs.QuestionScore IS NULL -- user may have no recent questions
        OR qs.QuestionScore >= -5
    )
GROUP BY
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.NumPosts,
    au.NumBadges,
    au.NumAnswers,
    au.NumQuestions,
    au.ReputationRank,
    aha.NumHighScoreAnswers
HAVING
    (AVG(qs.QuestionScore) IS NULL OR AVG(qs.QuestionScore) > -2)
ORDER BY
    COALESCE(aha.NumHighScoreAnswers,0) DESC,
    au.Reputation DESC
LIMIT 100;