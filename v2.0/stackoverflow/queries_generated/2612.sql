-- {"query": "2612.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2148} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id, t.TagName, t.Count,
        ARRAY[t.TagName] AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id, t.TagName, t.Count,
        r.TagPath || t.TagName,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.WikiPostId = r.Id
    WHERE t.IsModeratorOnly = 0 AND r.Level < 3
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswerCount,
        COALESCE(COUNT(DISTINCT b.Id),0) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AveragePostScore,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
RecentHighImpactQuestions AS (
    SELECT
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
        ARRAY_TO_STRING(
            ARRAY(
                SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><'))
            ), ', '
        ) AS TagList,
        COALESCE(
            (
                SELECT UNNEST(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><'))
                INTERSECT
                SELECT TagName FROM Tags WHERE Count > 10000
            )::varchar,
        'None') AS PopularIntersectTag,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
      AND p.Score >= 10
),
UserRecentEditsWithCloseVotes AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS RecentEdits,
        COUNT(DISTINCT ph_close.Id) AS CloseVotesCast,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - u.CreationDate))/86400) AS AvgDaysAfterUserCreationForEdits
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
    LEFT JOIN PostHistory ph_close ON ph_close.UserId = u.Id AND ph_close.PostHistoryTypeId = 10 AND ph_close.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) > 5
       OR COUNT(DISTINCT ph_close.Id) > 0
),
CombinedPostsAndComments AS (
    SELECT
        p.Id AS ItemId,
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Title AS ContentTitle,
        NULL::varchar AS CommentText,
        'Post' AS ItemType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)

    UNION ALL

    SELECT
        c.Id AS ItemId,
        c.UserId,
        NULL AS PostTypeId,
        c.Score,
        c.CreationDate,
        NULL::varchar AS ContentTitle,
        c.Text AS CommentText,
        'Comment' AS ItemType
    FROM Comments c
),
DenseRankedActivity AS (
    SELECT
        UserId,
        ItemType,
        Score,
        CreationDate,
        DENSE_RANK() OVER (PARTITION BY UserId, ItemType ORDER BY Score DESC, CreationDate DESC) AS ScoreRankDesc
    FROM CombinedPostsAndComments
    WHERE Score IS NOT NULL
),
TopUserActivities AS (
    SELECT
        UserId,
        ItemType,
        Score,
        CreationDate
    FROM DenseRankedActivity
    WHERE ScoreRankDesc <= 5
),
LinkAnalysis AS (
    SELECT
        pl.Id, pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        EXISTS (
            SELECT 1
            FROM PostHistory ph
            WHERE ph.PostId = pl.PostId AND ph.PostHistoryTypeId = 10
        ) AS PostHasCloseHistory,
        (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.PostId = pl.PostId AND pl2.LinkTypeId = 3) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    LEFT JOIN Posts p1 ON p1.Id = pl.PostId
    LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
),
FinalStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.BadgeCount,
        COALESCE(u.Reputation, 0) AS Reputation,
        uas.AveragePostScore,
        rhe.CloseVotesCast,
        rhe.RecentEdits,
        rh.LastEditDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotes,
        COALESCE(COUNT(DISTINCT b.Id), 0) AS TotalBadges,
        COALESCE(MAX(p.Score), 0) AS MaxPostScore
    FROM Users u
    LEFT JOIN UserActivitySummary uas ON uas.UserId = u.Id
    LEFT JOIN UserRecentEditsWithCloseVotes rhe ON rhe.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT MAX(ph.CreationDate) AS LastEditDate
        FROM PostHistory ph
        WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)
    ) rh ON TRUE
    GROUP BY u.Id, u.DisplayName, uas.QuestionCount, uas.AnswerCount, uas.BadgeCount, u.Reputation,
             uas.AveragePostScore, rhe.CloseVotesCast, rhe.RecentEdits, rh.LastEditDate
    HAVING (uas.QuestionCount + uas.AnswerCount) > 10 AND u.Reputation > 1000
    ORDER BY Reputation DESC, MaxPostScore DESC
    LIMIT 20
)
SELECT
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.QuestionCount,
    f.AnswerCount,
    f.BadgeCount,
    ROUND(f.AveragePostScore::numeric, 2) AS AvgScore,
    f.RecentEdits,
    f.CloseVotesCast,
    f.LastEditDate,
    f.TotalUpvotes,
    f.TotalDownvotes,
    f.TotalBadges,
    f.MaxPostScore,
    rh.PopularIntersectTag,
    rh.Title AS SampleHighImpactQuestion,
    rh.CreationDate AS QuestionDate,
    la.LinkTypeName,
    la.PostHasCloseHistory,
    la.DuplicateLinkCount,
    STRING_AGG(DISTINCT rth.TagName, ' > ') AS TagHierarchyPath,
    STRING_AGG(DISTINCT tua.ItemType || ':' || COALESCE(tua.Score::text, '?'), ', ') AS TopActivitiesByUser
FROM FinalStats f
LEFT JOIN RecentHighImpactQuestions rh ON rh.Id = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = f.UserId AND p.Score >= 10 ORDER BY p.Score DESC, p.CreationDate DESC LIMIT 1
)
LEFT JOIN LinkAnalysis la ON la.PostId = rh.Id
LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY(string_to_array(COALESCE(rh.TagList,''), ', '))
LEFT JOIN TopUserActivities tua ON tua.UserId = f.UserId
GROUP BY
    f.UserId, f.DisplayName, f.Reputation, f.QuestionCount, f.AnswerCount, f.BadgeCount,
    f.AveragePostScore, f.RecentEdits, f.CloseVotesCast, f.LastEditDate,
    f.TotalUpvotes, f.TotalDownvotes, f.TotalBadges, f.MaxPostScore,
    rh.PopularIntersectTag, rh.Title, rh.CreationDate,
    la.LinkTypeName, la.PostHasCloseHistory, la.DuplicateLinkCount
ORDER BY f.Reputation DESC, f.MaxPostScore DESC
LIMIT 20;
