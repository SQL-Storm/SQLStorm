-- {"query": "33064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 681} 
WITH TagUsage AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        AVG(p.Score) AS AverageScore
    FROM
        Posts p
        JOIN Tags t ON p.Tags @> ARRAY[t.TagName]
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.OwnerUserId <> -1 -- Exclude deleted users
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY
        t.TagName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AND p2.ParentId IS NOT NULL AS AnswersPosted
    FROM
        Users u
        LEFT JOIN Votes v ON u.Id = v.UserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
        LEFT JOIN Posts p2 ON u.Id = p2.OwnerUserId AND p2.PostTypeId = 2
    GROUP BY
        u.Id, u.DisplayName
),
PostHistoryCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) AS RevisionCount
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
)
SELECT
    'Performance Benchmark Snapshot' AS Description,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate,
    COUNT(DISTINCT u.Id) AS ActiveUsers,
    AVG(u.Reputation) AS AvgUserReputation,
    JSON_AGG(ROW(t.TagName, t.UniqueContributors, t.AverageScore)) AS TopTagsUsage,
    JSON_AGG(ROW(ua.UserId, ua.DisplayName, ua.UpVotesGiven, ua.DownVotesGiven, ua.CommentCount, ua.QuestionsPosted, ua.AnswersPosted)) AS UserActivities,
    JSON_AGG(ROW(p.Id, pc.RevisionCount)) AS PostRevisions
FROM
    Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN TagUsage t ON p.Tags @> ARRAY[t.TagName]
    LEFT JOIN UserActivity ua ON u.Id = ua.UserId
    LEFT JOIN PostHistoryCounts pc ON p.Id = pc.PostId
WHERE
    p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= NOW() - INTERVAL '1 year'