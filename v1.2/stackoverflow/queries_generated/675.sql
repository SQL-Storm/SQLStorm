-- {"query": "675.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2100} 

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
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r ON t.Id = r.Id + 1
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadgeNames
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        COUNT(a.Id) AS AnswerCount,
        AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score, q.ViewCount, q.Tags, q.AcceptedAnswerId
),
AnswerDetailWithVotes AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate
),
TopAnswersWithComments AS (
    SELECT
        a.AnswerId,
        a.QuestionId,
        a.OwnerUserId,
        a.AnswerScore,
        a.AnswerCreation,
        a.UpVotes,
        a.DownVotes,
        a.TotalBounty,
        c.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY a.QuestionId ORDER BY a.AnswerScore DESC, a.AnswerCreation ASC) AS RankPerQuestion
    FROM AnswerDetailWithVotes a
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON a.AnswerId = c.PostId
    WHERE a.AnswerRank <= 3
),
CloseReasonSummary AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON TRY_CAST(ph.Comment AS smallint) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(COALESCE(v.VoteTypeId = 2::int, 0)) OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpVotes,
        SUM(COALESCE(v.VoteTypeId = 3::int, 0)) OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeDownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
CombinedPostsAndLinks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
FilteredComplexQuery AS (
    SELECT
        qas.QuestionId,
        qas.Title AS QuestionTitle,
        qas.QuestionCreation,
        qas.OwnerUserId,
        ubc.DisplayName AS OwnerName,
        qas.Score AS QuestionScore,
        qas.ViewCount,
        qas.Tags,
        qas.AnswerCount,
        qas.AvgAnswerScore,
        tas.AnswerId,
        tas.AnswerScore,
        tas.UpVotes,
        tas.DownVotes,
        tas.TotalBounty,
        tas.CommentCount AS AnswerCommentCount,
        crs.CloseReason,
        crs.CloseCount,
        ROW_NUMBER() OVER (PARTITION BY qas.QuestionId ORDER BY tas.AnswerScore DESC NULLS LAST) AS AnswerRanking
    FROM QuestionAnswerStats qas
    LEFT JOIN TopAnswersWithComments tas ON qas.QuestionId = tas.QuestionId
    LEFT JOIN CloseReasonSummary crs ON qas.QuestionId = crs.PostId
    LEFT JOIN Users ubc ON qas.OwnerUserId = ubc.Id
    WHERE qas.ViewCount > 1000
      AND (qas.Score > 5 OR qas.AnswerCount > 2)
      AND (tas.AnswerScore IS NULL OR tas.AnswerScore >= 0)
),
FinalResult AS (
    SELECT
        fcq.QuestionId,
        fcq.QuestionTitle,
        fcq.OwnerName,
        fcq.QuestionCreation,
        fcq.QuestionScore,
        fcq.ViewCount,
        fcq.Tags,
        fcq.AnswerCount,
        fcq.AvgAnswerScore,
        fcq.AnswerId,
        fcq.AnswerScore,
        fcq.UpVotes,
        fcq.DownVotes,
        fcq.TotalBounty,
        fcq.AnswerCommentCount,
        fcq.CloseReason,
        fcq.CloseCount,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.DistinctBadgeNames,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.CumulativeUpVotes,
        ua.CumulativeDownVotes,
        ROW_NUMBER() OVER (PARTITION BY fcq.QuestionId ORDER BY fcq.AnswerScore DESC NULLS LAST) AS RankPerQuestion
    FROM FilteredComplexQuery fcq
    LEFT JOIN UserBadgeCounts ubc ON fcq.OwnerUserId = ubc.UserId
    LEFT JOIN UserActivityWindow ua ON fcq.OwnerUserId = ua.UserId
    WHERE fcq.AnswerRanking <= 3 OR fcq.AnswerRanking IS NULL
)
SELECT
    fr.QuestionId,
    fr.QuestionTitle,
    fr.OwnerName,
    fr.QuestionCreation,
    fr.QuestionScore,
    fr.ViewCount,
    COALESCE(fr.Tags, '') AS Tags,
    fr.AnswerCount,
    ROUND(fr.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    fr.AnswerId,
    fr.AnswerScore,
    fr.UpVotes,
    fr.DownVotes,
    fr.TotalBounty,
    fr.AnswerCommentCount,
    fr.CloseReason,
    fr.CloseCount,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.DistinctBadgeNames,
    fr.QuestionsAsked,
    fr.AnswersGiven,
    fr.CommentsMade,
    fr.CumulativeUpVotes,
    fr.CumulativeDownVotes,
    CASE
        WHEN fr.QuestionScore > 50 THEN 'High Score'
        WHEN fr.QuestionScore BETWEEN 10 AND 50 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    CASE
        WHEN fr.CloseReason IS NOT NULL THEN CONCAT('Closed: ', fr.CloseReason)
        ELSE 'Open'
    END AS PostStatus,
    LENGTH(fr.QuestionTitle) AS TitleLength,
    CASE
        WHEN fr.Tags LIKE '%<sql>%' THEN TRUE
        ELSE FALSE
    END AS HasSQLTag
FROM FinalResult fr
ORDER BY fr.QuestionScore DESC NULLS LAST, fr.ViewCount DESC NULLS LAST, fr.AnswerScore DESC NULLS LAST
LIMIT 100;
