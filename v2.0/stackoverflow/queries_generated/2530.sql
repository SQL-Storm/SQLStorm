-- {"query": "2530.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1728} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS AncestorTags,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        r.AncestorTags || t2.TagName,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Id > r.Id
    WHERE r.Level < 2
),
UserReputationFiltered AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC NULLS LAST) AS LocationRank
    FROM Users u
    WHERE u.Reputation >= 1000 AND u.Location IS NOT NULL
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC NULLS LAST) AS RankByViews
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.CreationDate > (CURRENT_DATE - INTERVAL '2 years')
),
AnswerAggregates AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AverageAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswerWithOwnerCount,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionLinkDuplicates AS (
    SELECT
        pl.PostId AS QuestionId,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS TotalBadges,
        STRING_AGG(DISTINCT b.Name, ',' ORDER BY b.Name) AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Name IN ('BountyStart', 'BountyClose')) AS BountyEvents,
        SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Votes v
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
QuestionCommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AverageCommentScore,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS CommentsByRegisteredUsers
    FROM Comments c
    GROUP BY c.PostId
),
FinalAggregated AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        u.Id AS OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(a.AnswerCount, 0) AS AnswersCount,
        COALESCE(a.AverageAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(d.DuplicateCount, 0) AS DuplicateLinks,
        COALESCE(d.LinkedCount, 0) AS LinkedPosts,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(v.UpVotes, 0) AS UserUpVotes,
        COALESCE(v.DownVotes, 0) AS UserDownVotes,
        COALESCE(cmt.CommentCount, 0) AS CommentsCount,
        COALESCE(cmt.AverageCommentScore, 0) AS AvgCommentScore,
        COALESCE(cmt.CommentsByRegisteredUsers, 0) AS RegUserComments,
        RANK() OVER (PARTITION BY u.Location ORDER BY q.ViewCount DESC) AS RankInLocationByViews,
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Not Accepted'
        END AS AcceptanceStatus,
        LEFT(q.Title, 50) || '...' AS ShortTitle,
        LENGTH(q.Tags) AS TagStringLength,
        CASE
            WHEN q.ClosedDate IS NULL THEN 'Open'
            ELSE 'Closed'
        END AS PostStatus
    FROM TopQuestions q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN AnswerAggregates a ON a.QuestionId = q.Id
    LEFT JOIN QuestionLinkDuplicates d ON d.QuestionId = q.Id
    LEFT JOIN UserBadgeSummary b ON b.UserId = u.Id
    LEFT JOIN UserVoteStats v ON v.UserId = u.Id
    LEFT JOIN QuestionCommentStats cmt ON cmt.PostId = q.Id
    WHERE u.Reputation > 2000
)
SELECT
    fq.QuestionId,
    fq.ShortTitle,
    fq.OwnerUserId,
    fq.DisplayName,
    fq.Reputation,
    fq.Location,
    fq.AcceptanceStatus,
    fq.QuestionScore,
    fq.ViewCount,
    fq.AnswersCount,
    fq.AvgAnswerScore,
    fq.DuplicateLinks,
    fq.LinkedPosts,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.UserUpVotes,
    fq.UserDownVotes,
    fq.CommentsCount,
    fq.AvgCommentScore,
    fq.RegUserComments,
    fq.RankInLocationByViews,
    fq.TagStringLength,
    fq.PostStatus,
    STRING_AGG(DISTINCT th.TagName, ', ') WITHIN GROUP (ORDER BY th.TagName) AS RelatedTags,
    MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS LastCloseDate,
    COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseCount
FROM FinalAggregated fq
LEFT JOIN RecursiveTagHierarchy th ON POSITION(th.TagName IN fq.Tags) > 0
LEFT JOIN PostHistory ph ON ph.PostId = fq.QuestionId
GROUP BY
    fq.QuestionId,
    fq.ShortTitle,
    fq.OwnerUserId,
    fq.DisplayName,
    fq.Reputation,
    fq.Location,
    fq.AcceptanceStatus,
    fq.QuestionScore,
    fq.ViewCount,
    fq.AnswersCount,
    fq.AvgAnswerScore,
    fq.DuplicateLinks,
    fq.LinkedPosts,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.UserUpVotes,
    fq.UserDownVotes,
    fq.CommentsCount,
    fq.AvgCommentScore,
    fq.RegUserComments,
    fq.RankInLocationByViews,
    fq.TagStringLength,
    fq.PostStatus
ORDER BY fq.ViewCount DESC, fq.QuestionScore DESC
LIMIT 50
;
