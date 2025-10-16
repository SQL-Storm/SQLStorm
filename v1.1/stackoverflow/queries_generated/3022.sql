-- {"query": "3022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 930} 
WITH UserAnswerStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS UpvotedAnswers,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM
        Users u
        LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    GROUP BY
        u.Id, u.DisplayName
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
QuestionAnswers AS (
    SELECT
        q.QuestionId,
        a.Id AS AnswerId,
        a.Score,
        a.CreationDate AS AnswerDate,
        a.OwnerUserId AS AnswerOwner
    FROM
        RecentQuestions q
        LEFT JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
),
AnswerAnswerChain AS (
    SELECT
        a1.AnswerId,
        a2.AnswerId AS FollowUpAnswerId,
        a2.Score AS FollowUpScore,
        a2.CreationDate AS FollowUpDate
    FROM
        QuestionAnswers a1
        LEFT JOIN Posts a2 ON a2.ParentId = a1.AnswerId AND a2.PostTypeId = 2
),
ActiveUsers AS (
    SELECT DISTINCT
        u.Id
    FROM
        Users u
        INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId IN (1, 2)
        AND u.LastAccessDate >= NOW() - INTERVAL '180 days'
),
ComplexMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT q.QuestionId) FILTER (WHERE q.CreationDate >= NOW() - INTERVAL '60 days') AS RecentQuestionsCount,
        COUNT(DISTINCT a.AnswerId) FILTER (WHERE a.AnswerDate >= NOW() - INTERVAL '60 days') AS RecentAnswersCount,
        COUNT(DISTINCT aa.FollowUpAnswerId) FILTER (WHERE aa.FollowUpDate >= NOW() - INTERVAL '60 days') AS FollowUpAnswersCount,
        COALESCE(SUM(a.Score), 0) AS TotalScoreAnswers,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalPostsByUser,
        MAX(p.LastActivityDate) OVER (PARTITION BY u.Id) AS LastActivity
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN QuestionAnswers a ON u.Id = a.AnswerOwner
        LEFT JOIN AnswerAnswerChain aa ON u.Id = aa.AnswerOwner
    WHERE
        u.Id IN (SELECT Id FROM ActiveUsers)
    GROUP BY
        u.Id, u.DisplayName
)
SELECT
    um.UserId,
    um.DisplayName,
    um.RecentQuestionsCount,
    um.RecentAnswersCount,
    um.FollowUpAnswersCount,
    um.TotalScoreAnswers,
    um.TotalPostsByUser,
    um.LastActivity,
    CASE
        WHEN um.RecentQuestionsCount > 0 THEN (um.RecentAnswersCount::float / um.RecentQuestionsCount)
        ELSE NULL
    END AS AnswerQuestionRatio,
    CASE
        WHEN um.RecentAnswersCount > 0 THEN (um.FollowUpAnswersCount::float / um.RecentAnswersCount)
        ELSE NULL
    END AS FollowUpAnswerRatio,
    STRING_AGG(DISTINCT t.TagName, ',') AS UniqueTags
FROM
    ComplexMetrics um
    LEFT JOIN Posts p ON p.OwnerUserId = um.UserId AND p.PostTypeId = 1
    LEFT JOIN unnest(string_to_array(p.Tags, '><')) AS tag ON TRUE
        LEFT JOIN Tags t ON t.TagName = tag
GROUP BY
    um.UserId,
    um.DisplayName,
    um.RecentQuestionsCount,
    um.RecentAnswersCount,
    um.FollowUpAnswersCount,
    um.TotalScoreAnswers,
    um.TotalPostsByUser,
    um.LastActivity;