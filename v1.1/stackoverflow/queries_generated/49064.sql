-- {"query": "49064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2349} 

WITH TopPerformingQuestions AS (
    -- Identify questions that are highly viewed, scored, and have a significant number of answers within a recent period
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate AS QuestionCreationDate,
        p.Tags,
        p.AcceptedAnswerId
    FROM Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.ViewCount >= 250000 -- Significantly high view count
        AND p.Score >= 1000 -- Very high score
        AND p.AnswerCount >= 20 -- At least 20 answers
        AND p.CreationDate >= '2020-01-01' -- Created in the last few years
),
TopPerformingAnswers AS (
    -- Identify answers that are either accepted for TopPerformingQuestions or are highly scored answers to them
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.ParentId AS QuestionId,
        a.CreationDate AS AnswerCreationDate,
        TRUE AS IsAcceptedAnswer
    FROM Posts a
    JOIN TopPerformingQuestions tpq ON a.ParentId = tpq.QuestionId
    WHERE
        a.PostTypeId = 2 -- Only answers
        AND a.Id = tpq.AcceptedAnswerId -- This answer was accepted for a top question
    UNION ALL
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.ParentId AS QuestionId,
        a.CreationDate AS AnswerCreationDate,
        FALSE AS IsAcceptedAnswer
    FROM Posts a
    JOIN TopPerformingQuestions tpq ON a.ParentId = tpq.QuestionId
    WHERE
        a.PostTypeId = 2 -- Only answers
        AND a.Id <> tpq.AcceptedAnswerId -- Not the accepted answer
        AND a.Score >= 500 -- But still highly scored
),
HighlyEngagedUsers AS (
    -- Collect all unique user IDs involved in these top performing questions and answers,
    -- including owners, editors, commenters, and up/accepted voters.
    SELECT OwnerUserId AS UserId FROM TopPerformingQuestions WHERE OwnerUserId IS NOT NULL
    UNION
    SELECT AnswerOwnerUserId AS UserId FROM TopPerformingAnswers WHERE AnswerOwnerUserId IS NOT NULL
    UNION
    SELECT c.UserId FROM Comments c JOIN TopPerformingQuestions tpq ON c.PostId = tpq.QuestionId WHERE c.UserId IS NOT NULL
    UNION
    SELECT c.UserId FROM Comments c JOIN TopPerformingAnswers tpa ON c.PostId = tpa.AnswerId WHERE c.UserId IS NOT NULL
    UNION
    SELECT v.UserId FROM Votes v JOIN TopPerformingQuestions tpq ON v.PostId = tpq.QuestionId WHERE v.UserId IS NOT NULL AND v.VoteTypeId IN (1,2) -- AcceptedByOriginator, UpMod
    UNION
    SELECT v.UserId FROM Votes v JOIN TopPerformingAnswers tpa ON v.PostId = tpa.AnswerId WHERE v.UserId IS NOT NULL AND v.VoteTypeId IN (1,2) -- AcceptedByOriginator (for answers), UpMod
    UNION
    SELECT ph.UserId FROM PostHistory ph JOIN TopPerformingQuestions tpq ON ph.PostId = tpq.QuestionId WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4,5,6) -- Edit Title/Body/Tags
),
UserOverallActivity AS (
    -- Summarize general activity for highly engaged users, including total posts, scores, and badges.
    SELECT
        heu.UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(p.Score) AS TotalPostsScore,
        AVG(p.Score) AS AveragePostScore,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        -- Count distinct questions for which this user provided the accepted answer
        COUNT(DISTINCT q_accepted.Id) AS AcceptedAnswersProvidedCount
    FROM HighlyEngagedUsers heu
    JOIN Users u ON heu.UserId = u.Id
    LEFT JOIN Posts p ON heu.UserId = p.OwnerUserId
    LEFT JOIN Badges b ON heu.UserId = b.UserId
    LEFT JOIN Posts q_accepted ON q_accepted.PostTypeId = 1 AND p.PostTypeId = 2 AND q_accepted.AcceptedAnswerId = p.Id AND p.OwnerUserId = heu.UserId
    GROUP BY heu.UserId, u.DisplayName, u.Reputation, u.CreationDate
),
UserTagDominance AS (
    -- Identify the top 3 most impactful tags for each highly engaged user based on combined score of their questions
    SELECT
        UserId,
        ARRAY_AGG(TagName ORDER BY TagImpactScore DESC, TagQuestionCount DESC) FILTER (WHERE rn <= 3) AS Top3TagsByImpact
    FROM (
        SELECT
            ua.UserId,
            t.TagName,
            COUNT(DISTINCT pq.QuestionId) AS TagQuestionCount,
            SUM(pq.QuestionScore) AS TagImpactScore,
            ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY SUM(pq.QuestionScore) DESC, COUNT(DISTINCT pq.QuestionId) DESC) as rn
        FROM UserOverallActivity ua
        JOIN TopPerformingQuestions pq ON ua.UserId = pq.OwnerUserId
        CROSS JOIN UNNEST(string_to_array(substring(pq.Tags, 2, length(pq.Tags) - 2), '><')) AS t(TagName)
        WHERE t.TagName IS NOT NULL AND t.TagName <> ''
        GROUP BY ua.UserId, t.TagName
    ) AS UserTagsAgg
    GROUP BY UserId
),
PostLifecycleMetrics AS (
    -- Analyze the editing and closing/reopening history for top-performing questions
    SELECT
        tpq.QuestionId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditEventsCount, -- Edits (Title, Body, Tags)
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) AS CloseReopenEventsCount, -- Post Closed/Reopened
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        MAX(ph.CreationDate) AS LastHistoryEventDate
    FROM TopPerformingQuestions tpq
    JOIN PostHistory ph ON tpq.QuestionId = ph.PostId
    GROUP BY tpq.QuestionId
)
-- Final selection: Rank highly engaged users based on a composite score reflecting their overall contribution and impact
SELECT
    uoa.UserId,
    uoa.DisplayName,
    uoa.Reputation,
    uoa.UserCreationDate,
    uoa.TotalPostsOwned,
    uoa.QuestionsAsked,
    uoa.AnswersGiven,
    uoa.TotalPostsScore,
    uoa.AveragePostScore,
    uoa.BadgesCount,
    uoa.AcceptedAnswersProvidedCount,
    utd.Top3TagsByImpact,
    -- Aggregated metrics for questions owned by this user that are in TopPerformingQuestions
    COALESCE(SUM(DISTINCT tpq_owned.QuestionScore), 0) AS TotalOwnedQuestionScore_TPQ,
    COALESCE(SUM(DISTINCT tpq_owned.ViewCount), 0) AS TotalOwnedQuestionViews_TPQ,
    COALESCE(SUM(DISTINCT tpq_owned.AnswerCount), 0) AS TotalOwnedQuestionAnswers_TPQ,
    -- Aggregated metrics for answers provided by this user that are in TopPerformingAnswers
    COALESCE(SUM(tpa_provided.AnswerScore), 0) AS TotalAnswerScore_TPA,
    COUNT(tpa_provided.AnswerId) AS TotalAnswersProvidedInTPQ,
    SUM(CASE WHEN tpa_provided.IsAcceptedAnswer THEN 1 ELSE 0 END) AS AcceptedAnswersProvidedInTPQ,
    -- Combined lifecycle metrics for questions owned by this user
    COALESCE(SUM(qlm.TotalHistoryEvents), 0) AS TotalHistoryEvents_OwnedQuestions,
    COALESCE(SUM(qlm.EditEventsCount), 0) AS TotalEditEvents_OwnedQuestions,
    COALESCE(AVG(EXTRACT(EPOCH FROM (qlm.LastHistoryEventDate - qlm.FirstHistoryEventDate)) / 86400), 0) AS AvgQuestionActiveDays_OwnedQuestions
FROM UserOverallActivity uoa
LEFT JOIN UserTagDominance utd ON uoa.UserId = utd.UserId
LEFT JOIN TopPerformingQuestions tpq_owned ON uoa.UserId = tpq_owned.OwnerUserId
LEFT JOIN TopPerformingAnswers tpa_provided ON uoa.UserId = tpa_provided.AnswerOwnerUserId
LEFT JOIN PostLifecycleMetrics qlm ON tpq_owned.QuestionId = qlm.QuestionId
GROUP BY
    uoa.UserId, uoa.DisplayName, uoa.Reputation, uoa.UserCreationDate,
    uoa.TotalPostsOwned, uoa.QuestionsAsked, uoa.AnswersGiven, uoa.TotalPostsScore,
    uoa.AveragePostScore, uoa.BadgesCount, uoa.AcceptedAnswersProvidedCount, utd.Top3TagsByImpact
ORDER BY
    (uoa.Reputation * 0.4) +
    (uoa.TotalPostsScore * 0.2) +
    (uoa.AcceptedAnswersProvidedCount * 50) +
    (uoa.BadgesCount * 5) +
    (COALESCE(SUM(DISTINCT tpq_owned.QuestionScore), 0) * 0.1) +
    (COALESCE(SUM(tpa_provided.AnswerScore), 0) * 0.1)
    DESC
LIMIT 100;
