-- {"query": "543.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1600} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rh.Level + 1,
        rh.Path || child.TagName
    FROM Tags child
    JOIN Posts p ON p.Tags LIKE '%' || '<' || child.TagName || '>' || '%'
    JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY (string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
    WHERE child.IsRequired = 0 AND NOT child.TagName = ANY(rh.Path)
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserActivityWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.LastAccessDate DESC) AS UserRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
),
PostScoreAggregates AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        SUM(COALESCE(v.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
        COUNT(v.Id) OVER (PARTITION BY p.Id) AS VoteCount,
        AVG(COALESCE(v.BountyAmount, 0)) OVER (PARTITION BY p.Id) AS AvgBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
),
LatestCommentsPerPost AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Id AS CommentId,
        c.UserId AS CommentUserId,
        c.UserDisplayName AS CommentUserDisplayName,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS CommentRank
    FROM Comments c
    WHERE c.Text IS NOT NULL
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
QuestionsWithAcceptedAnswer AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.OwnerUserId AS AcceptedAnswerOwner,
        a.CreationDate AS AnswerCreationDate
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1
),
ComplexUserPostStats AS (
    SELECT
        ua.Id AS UserId,
        ua.DisplayName,
        COUNT(DISTINCT q.QuestionId) AS TotalQuestions,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        AVG(q.QuestionScore) FILTER (WHERE q.QuestionScore IS NOT NULL) AS AvgQuestionScore,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        MAX(q.ViewCount) FILTER (WHERE q.ViewCount IS NOT NULL) AS MaxQuestionViews,
        SUM(COALESCE(pls.LinkedCount,0)) AS TotalLinkedPosts,
        SUM(COALESCE(pls.DuplicateCount,0)) AS TotalDuplicatePosts,
        MAX(COALESCE(ph.PostHistoryTypeId,0)) AS MaxPostHistoryTypeId,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS CloseReopenEvents,
        COUNT(DISTINCT c.Id) FILTER (WHERE c.UserId = ua.Id) AS UserCommentCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges
    FROM UserActivityWindow ua
    LEFT JOIN QuestionsWithAcceptedAnswer q ON q.OwnerUserId = ua.Id
    LEFT JOIN Posts a ON a.PostTypeId = 2 AND a.OwnerUserId = ua.Id
    LEFT JOIN PostLinkSummary pls ON pls.PostId = q.QuestionId OR pls.PostId = a.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId OR ph.PostId = a.Id
    LEFT JOIN Comments c ON c.UserId = ua.Id
    GROUP BY ua.Id, ua.DisplayName, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges
),
RankedUserStats AS (
    SELECT
        *,
        RANK() OVER (ORDER BY TotalQuestions DESC, TotalAnswers DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC) AS OverallRank
    FROM ComplexUserPostStats
)
SELECT
    rus.UserId,
    rus.DisplayName,
    rus.TotalQuestions,
    rus.TotalAnswers,
    rus.AvgQuestionScore,
    rus.AvgAnswerScore,
    rus.MaxQuestionViews,
    rus.TotalLinkedPosts,
    rus.TotalDuplicatePosts,
    rus.CloseReopenEvents,
    rus.UserCommentCount,
    rus.GoldBadges,
    rus.SilverBadges,
    rus.BronzeBadges,
    rh.Level AS TagHierarchyLevel,
    rh.Path AS TagHierarchyPath
FROM RankedUserStats rus
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
    FROM Posts p WHERE p.OwnerUserId = rus.UserId LIMIT 1
)
WHERE rus.OverallRank <= 100
ORDER BY rus.OverallRank, rh.Level DESC NULLS LAST;
