-- {"query": "278.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2157} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id = r.Id + 1
    WHERE r.Level < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(COALESCE(vtUp.CountUpVotes,0)),0) AS TotalUpVotes,
        COALESCE(SUM(COALESCE(vtDown.CountDownVotes,0)),0) AS TotalDownVotes,
        u.Reputation,
        u.CreationDate,
        u.Location
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS CountUpVotes
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId = 2
        GROUP BY p.OwnerUserId
    ) vtUp ON vtUp.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS CountDownVotes
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId = 3
        GROUP BY p.OwnerUserId
    ) vtDown ON vtDown.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByUser,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalViewsByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CloseReasonCounts AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment ~ '^\d+$'
    GROUP BY ph.PostId, crt.Name
),
PostWithCloseInfo AS (
    SELECT
        p.*,
        crc.CloseReason,
        crc.CloseCount
    FROM Posts p
    LEFT JOIN CloseReasonCounts crc ON crc.PostId = p.Id
),
UserTopTags AS (
    SELECT
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY u.Id, Tag
),
UserTopTagRanked AS (
    SELECT
        UserId,
        Tag,
        TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS TagRank
    FROM UserTopTags
),
UserTop3Tags AS (
    SELECT UserId, Tag, TagCount
    FROM UserTopTagRanked
    WHERE TagRank <= 3
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerExists
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, q.AcceptedAnswerId
),
UserActivitySummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(pa.TotalPostsByUser, 0) AS TotalPosts,
        COALESCE(pa.AvgScoreByUser, 0) AS AvgPostScore,
        COALESCE(pa.TotalViewsByUser, 0) AS TotalViews,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ub.TotalUpVotes, 0) AS TotalUpVotes,
        COALESCE(ub.TotalDownVotes, 0) AS TotalDownVotes,
        COALESCE(ut3.Tag, 'NoTag') AS TopTag,
        COALESCE(ut3.TagCount, 0) AS TopTagCount
    FROM Users u
    LEFT JOIN PostActivityWindow pa ON pa.OwnerUserId = u.Id AND pa.RecentPostRank = 1
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN UserTop3Tags ut3 ON ut3.UserId = u.Id AND ut3.TagRank = 1
),
ComplexPostAnalysis AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        COALESCE(ac.AnswerCount, 0) AS AnswerCount,
        COALESCE(ac.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ac.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(ac.AcceptedAnswerExists, 0) AS HasAcceptedAnswer,
        pwci.CloseReason,
        pwci.CloseCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRankByUser,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN ac.AcceptedAnswerExists = 1 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeSnippetCount,
        CASE
            WHEN p.Tags IS NOT NULL THEN array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagCount
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN AnswerStats ac ON ac.QuestionId = p.Id
    LEFT JOIN PostWithCloseInfo pwci ON pwci.Id = p.Id
    WHERE p.PostTypeId = 1
),
FinalResult AS (
    SELECT
        cpa.Id AS QuestionId,
        cpa.Title,
        cpa.OwnerUserId,
        cpa.OwnerName,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.AvgAnswerScore,
        cpa.MaxAnswerScore,
        cpa.HasAcceptedAnswer,
        cpa.CloseReason,
        cpa.CloseCount,
        cpa.PostStatus,
        cpa.CodeSnippetCount,
        cpa.TagCount,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.TotalPosts,
        uas.AvgPostScore,
        uas.TotalViews,
        uas.TotalUpVotes,
        uas.TotalDownVotes,
        uas.TopTag,
        uas.TopTagCount,
        ROW_NUMBER() OVER (ORDER BY cpa.Score DESC, cpa.ViewCount DESC) AS GlobalRank
    FROM ComplexPostAnalysis cpa
    LEFT JOIN UserActivitySummary uas ON uas.Id = cpa.OwnerUserId
    WHERE cpa.Score > 5
)
SELECT
    fr.*,
    CASE
        WHEN fr.CloseReason IS NOT NULL THEN CONCAT('Closed due to: ', fr.CloseReason, ' (', fr.CloseCount, ' votes)')
        ELSE 'Not Closed'
    END AS CloseReasonDescription,
    CONCAT(
        'User ', COALESCE(fr.OwnerName, 'Unknown'), ' has ',
        fr.GoldBadges, ' gold, ',
        fr.SilverBadges, ' silver, and ',
        fr.BronzeBadges, ' bronze badges.'
    ) AS UserBadgeSummary,
    CONCAT(
        'Top tag: ', fr.TopTag, ' (', fr.TopTagCount, ' posts)'
    ) AS UserTopTagSummary,
    CASE
        WHEN fr.PostStatus = 'Closed' THEN 'No further answers allowed'
        WHEN fr.PostStatus = 'Answered' THEN 'Answered with accepted answer'
        ELSE 'Open for answers'
    END AS PostStatusDescription
FROM FinalResult fr
WHERE fr.GlobalRank <= 50
ORDER BY fr.GlobalRank;
