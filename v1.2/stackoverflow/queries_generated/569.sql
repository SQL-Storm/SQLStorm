-- {"query": "569.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1902} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        rth.TagPath || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.Id <> rth.Id
    WHERE t2.IsModeratorOnly = 0 AND t2.IsRequired = 0
      AND NOT t2.TagName = ANY(rth.TagPath)
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score IS NOT NULL
      AND p.ViewCount IS NOT NULL
),
TopAnswersWithAcceptedInfo AS (
    SELECT
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        q.AcceptedAnswerId,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS MaxPostScore,
        MIN(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS MinPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id
),
CloseReasonStats AS (
    SELECT
        crt.Id AS CloseReasonId,
        crt.Name AS CloseReasonName,
        COUNT(DISTINCT ph.PostId) AS ClosedPostsCount,
        AVG(EXTRACT(EPOCH FROM (ph.ClosedDate - p.CreationDate))/3600) AS AvgHoursToClose
    FROM CloseReasonTypes crt
    LEFT JOIN PostHistory ph ON ph.PostHistoryTypeId = 10 AND ph.Comment = CAST(crt.Id AS VARCHAR)
    LEFT JOIN Posts p ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY crt.Id, crt.Name
),
UserRankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS PostRank
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostTags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
TagPopularity AS (
    SELECT
        upt.TagName,
        COUNT(*) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM UserPostTags upt
    JOIN Posts p ON p.Id = upt.PostId
    GROUP BY upt.TagName
),
UserTopTags AS (
    SELECT
        upt.OwnerUserId,
        upt.TagName,
        COUNT(*) AS TagUsageCount,
        RANK() OVER (PARTITION BY upt.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM UserPostTags upt
    GROUP BY upt.OwnerUserId, upt.TagName
),
UserTopTagDetails AS (
    SELECT
        ut.OwnerUserId,
        ut.TagName,
        ut.TagUsageCount,
        tp.QuestionCount,
        tp.AvgScore,
        tp.TotalViews
    FROM UserTopTags ut
    LEFT JOIN TagPopularity tp ON tp.TagName = ut.TagName
    WHERE ut.TagRank <= 3
),
AcceptedAnswerDelays AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreation,
        a.Id AS AcceptedAnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreation,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAccept
    FROM Posts q
    JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
UserAnswerAcceptanceStats AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(*) AS AcceptedAnswersCount,
        AVG(h.HoursToAccept) AS AvgHoursToAccept
    FROM Posts a
    JOIN AcceptedAnswerDelays h ON h.AcceptedAnswerId = a.Id
    GROUP BY a.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    ua.TotalPosts,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.AvgPostScore,
    ua.MaxPostScore,
    ua.MinPostScore,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ars.ClosedPostsCount,
    ars.AvgHoursToClose,
    COALESCE(uaas.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(uaas.AvgHoursToAccept, NULL) AS AvgHoursToAccept,
    STRING_AGG(DISTINCT ut.TagName || ' (Count: ' || ut.TagUsageCount || ', AvgScore: ' || COALESCE(ROUND(ut.AvgScore::numeric,2),0) || ', Views: ' || COALESCE(ut.TotalViews,0) || ')', '; ') AS TopTags
FROM Users u
LEFT JOIN UserActivitySummary ua ON ua.UserId = u.Id
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
LEFT JOIN CloseReasonStats ars ON 1=1
LEFT JOIN UserAnswerAcceptanceStats uaas ON uaas.UserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, TagName, TagUsageCount, AvgScore, TotalViews
    FROM UserTopTagDetails
) ut ON ut.OwnerUserId = u.Id
WHERE ua.TotalPosts > 10
GROUP BY
    u.Id, u.DisplayName,
    ua.TotalPosts, ua.QuestionsCount, ua.AnswersCount, ua.CommentsCount,
    ua.UpVotesReceived, ua.DownVotesReceived, ua.AvgPostScore, ua.MaxPostScore, ua.MinPostScore,
    ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    ars.ClosedPostsCount, ars.AvgHoursToClose,
    uaas.AcceptedAnswersCount, uaas.AvgHoursToAccept
ORDER BY ua.TotalPosts DESC, ua.AvgPostScore DESC
LIMIT 100;
