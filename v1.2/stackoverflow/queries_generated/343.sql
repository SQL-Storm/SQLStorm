-- {"query": "343.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1818} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubc.Gold, 0) AS GoldBadges,
        COALESCE(ubc.Silver, 0) AS SilverBadges,
        COALESCE(ubc.Bronze, 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore,
        SUM(vs.UpVotes) AS TotalUpVotes,
        SUM(vs.DownVotes) AS TotalDownVotes
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS Bronze
        FROM UserBadgeCounts
        GROUP BY UserId
    ) ubc ON ubc.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) vs ON vs.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc.Gold, ubc.Silver, ubc.Bronze
),
PostWithComments AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        c.CommentCount,
        c.LatestCommentDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts p
    JOIN Posts q ON q.Id = p.ParentId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId, q.AcceptedAnswerId
),
PostHistoryCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),
CombinedUserActivity AS (
    SELECT
        ua.*,
        ura.LastPostDate,
        ura.LastCommentDate,
        ura.LastEditDate,
        COALESCE(ura.LastPostDate, '1900-01-01'::timestamp) > CURRENT_DATE - INTERVAL '30 days' AS ActiveInLast30Days
    FROM UserActivity ua
    LEFT JOIN UserRecentActivity ura ON ura.UserId = ua.UserId
)
SELECT DISTINCT
    cua.UserId,
    cua.DisplayName,
    cua.Reputation,
    cua.GoldBadges,
    cua.SilverBadges,
    cua.BronzeBadges,
    cua.QuestionsPosted,
    cua.AnswersPosted,
    cua.AvgPostScore,
    cua.MaxPostScore,
    cua.TotalUpVotes,
    cua.TotalDownVotes,
    cua.LastPostDate,
    cua.LastCommentDate,
    cua.LastEditDate,
    cua.ActiveInLast30Days,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.Tags,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    phcr.CloseReasonName,
    phcr.CloseVotesCount,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.AcceptedAnswerCount,
    STRING_AGG(DISTINCT rth.TagName, ', ') OVER (PARTITION BY p.Id) AS RelatedRequiredTags,
    ROW_NUMBER() OVER (PARTITION BY cua.UserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS UserPostRank,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus,
    CONCAT(
        'Score:', p.Score, '; ',
        'Views:', p.ViewCount, '; ',
        'Comments:', p.CommentCount, '; ',
        'Favorites:', p.FavoriteCount
    ) AS PostSummary,
    COALESCE(
        (SELECT AVG(v.BountyAmount)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId IN (8,9)
        ), 0) AS AvgBountyAmount
FROM CombinedUserActivity cua
LEFT JOIN Posts p ON p.OwnerUserId = cua.UserId
LEFT JOIN PostHistoryCloseReasons phcr ON phcr.PostId = p.Id
LEFT JOIN AnswerStats ans ON ans.QuestionId = p.Id AND p.PostTypeId = 1
LEFT JOIN RecursiveTagHierarchy rth ON POSITION(rth.TagName IN COALESCE(p.Tags, '')) > 0
WHERE cua.ActiveInLast30Days = TRUE
  AND (p.Score > 10 OR cua.GoldBadges > 0)
ORDER BY cua.Reputation DESC, p.Score DESC, p.ViewCount DESC
LIMIT 100;
