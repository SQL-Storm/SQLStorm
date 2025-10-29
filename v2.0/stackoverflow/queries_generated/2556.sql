-- {"query": "2556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1782} 

WITH RecursiveTagTree AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[LOWER(t.TagName)] AS TagPath,
        1 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        rtt.TagPath || LOWER(t2.TagName),
        rtt.Depth + 1
    FROM Tags t2
    JOIN RecursiveTagTree rtt ON LOWER(t2.TagName) > rtt.TagPath[array_length(rtt.TagPath, 1)]
    WHERE rtt.Depth < 3
),
UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2) AND p.Score IS NOT NULL) AS AveragePostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        MIN(u.CreationDate) AS UserSince,
        MAX(u.LastAccessDate) AS LastSeen,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score),0) DESC) AS ScoreRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
TopEngagedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 10
),
QuestionAnswerSummary AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.Tags,
        q.OwnerUserId AS QuestionOwner,
        uq.DisplayName AS QuestionOwnerName,
        q.CreationDate AS QuestionCreated,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.AcceptedAnswerId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        ua.Id AS AnswerOwnerId,
        ua.DisplayName AS AnswerOwnerName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerRank,
        COUNT(a.Id) OVER (PARTITION BY q.Id) AS TotalAnswers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users uq ON q.OwnerUserId = uq.Id
    LEFT JOIN Users ua ON a.OwnerUserId = ua.Id
    WHERE q.PostTypeId = 1
),
FilteredCloseReasons AS (
    SELECT ph.PostId, crt.Name as CloseReasonName, ph.CreationDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON cast(ph.Comment as integer) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
),
UserVoteAnalysis AS (
    SELECT 
        v.UserId,
        vt.Name as VoteTypeName,
        COUNT(v.Id) AS VoteCount,
        SUM(v.BountyAmount) AS TotalBountyGiven,
        MIN(v.CreationDate) AS FirstVoteDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.UserId, vt.Name
),
AnswerActivityWindow AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) AS AvgAnswerScore,
        COUNT(*) OVER (PARTITION BY a.ParentId) AS AnswersCount
    FROM Posts a
    WHERE a.PostTypeId = 2
),
CombinedPostTags AS (
    SELECT
        p.Id AS PostId,
        p.Tags,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagActivity AS (
    SELECT
        ct.Tag,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag,
        COUNT(DISTINCT a.Id) AS AnswersForTag,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(COALESCE(p.ViewCount,0)) AS TotalViews
    FROM CombinedPostTags ct
    LEFT JOIN Posts p ON p.Id = ct.PostId
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    GROUP BY ct.Tag
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.TotalPostScore,
    ua.AveragePostScore,
    ua.BadgeCount,
    CASE 
        WHEN ua.HighestBadgeClass = 1 THEN 'Gold' 
        WHEN ua.HighestBadgeClass = 2 THEN 'Silver'
        WHEN ua.HighestBadgeClass = 3 THEN 'Bronze'
        ELSE 'None'
    END AS HighestBadge,
    ua.CommentsCount,
    ua.UserSince,
    ua.LastSeen,
    ua.ScoreRank,
    tpt.Title AS TopQuestionTitle,
    tpt.Score AS TopQuestionScore,
    tpt.ViewCount AS TopQuestionViews,
    tpt.OwnerName AS TopQuestionOwner,
    tpA.Title AS TopAnswerTitle,
    tpA.Score AS TopAnswerScore,
    tpA.OwnerName AS TopAnswerOwner,
    qas.QuestionTitle,
    qas.TotalAnswers,
    qas.AnswerId,
    qas.AnswerScore,
    qas.AnswerOwnerName,
    fcr.CloseReasonName,
    uva.VoteTypeName,
    uva.VoteCount,
    uva.TotalBountyGiven,
    aaw.RankByScore,
    aaw.AvgAnswerScore,
    aaw.AnswersCount,
    ta.Tag,
    ta.QuestionsWithTag,
    ta.AnswersForTag,
    ta.AvgAnswerScore AS TagAvgAnswerScore,
    ta.TotalViews AS TagTotalViews,
    array_to_string(rtt.TagPath, ' > ') AS TagHierarchyPath
FROM UserPostActivity ua
LEFT JOIN TopEngagedPosts tpt ON tpt.rn = 1 AND tpt.PostTypeId = 1 AND tpt.OwnerUserId = ua.UserId
LEFT JOIN TopEngagedPosts tpA ON tpA.rn = 1 AND tpA.PostTypeId = 2 AND tpA.OwnerUserId = ua.UserId
LEFT JOIN QuestionAnswerSummary qas ON qas.AnswerOwnerId = ua.UserId AND qas.AnswerRank = 1
LEFT JOIN FilteredCloseReasons fcr ON fcr.PostId = qas.QuestionId
LEFT JOIN UserVoteAnalysis uva ON uva.UserId = ua.UserId
LEFT JOIN AnswerActivityWindow aaw ON aaw.Id = qas.AnswerId
LEFT JOIN TagActivity ta ON ta.Tag = ANY(
    SELECT unnest(string_to_array(substring(qas.Tags, 2, length(qas.Tags) - 2), '><'))
)
LEFT JOIN RecursiveTagTree rtt ON rtt.TagName = ta.Tag
WHERE ua.QuestionsCount > 0
ORDER BY ua.TotalPostScore DESC NULLS LAST
LIMIT 100;
