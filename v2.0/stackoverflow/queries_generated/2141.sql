-- {"query": "2141.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1560} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.ViewCount, 0) AS TagViewCount,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        rth.TagViewCount / 2, -- attenuate view count down the hierarchy
        rth.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.WikiPostId = rth.Id
    WHERE rth.Level < 3
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
PostScoreStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS ScoreRank,
        AVG(p.Score) OVER () AS AvgScore,
        CASE
            WHEN p.Tags IS NULL THEN ARRAY[]::text[]
            ELSE string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><')
        END AS TagList
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
AnsweredQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.CommentCount AS QuestionComments,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CommentCount AS AnswerComments,
        a.CreationDate AS AnswerCreationDate,
        a.Tags AS AnswerTags,
        q.ScoreRank AS QuestionScoreRank,
        q.AvgScore AS OverallAvgScore,
        q.TagList
    FROM PostScoreStats q
    JOIN PostScoreStats a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
TopLinkDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        ltp.Name AS LinkTypeName,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
    FROM PostLinks pl
    JOIN LinkTypes ltp ON ltp.Id = pl.LinkTypeId
    WHERE pl.LinkTypeId IN (1, 3)
),
UserActivityRanked AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        RANK() OVER (ORDER BY u.Reputation DESC, u.Views DESC NULLS LAST) AS UserRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
),
PostLastEditDetails AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.UserId AS LastEditorUserId,
        ph.UserDisplayName AS LastEditorDisplayName,
        ph.CreationDate AS LastEditDate,
        ph.PostHistoryTypeId,
        p.Title AS PostTitle
    FROM PostHistory ph
    JOIN Posts p ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- title/body/tags edits only
    ORDER BY ph.PostId, ph.CreationDate DESC
)
SELECT
    aq.QuestionId,
    aq.Title AS QuestionTitle,
    aq.QuestionScore,
    aq.QuestionComments,
    aq.AnswerId,
    COALESCE(uar.DisplayName, 'Unknown') AS AnswerOwner,
    aq.AnswerScore,
    aq.AnswerComments,
    aq.AnswerCreationDate,
    array_to_string(aq.TagList, ', ') AS Tags,
    COALESCE(MAX(tth.TagViewCount), 0) AS AggregateTagViewScore,
    tl.LinkTypeName AS TopLinkType,
    COALESCE(tl.RelatedPostId, 0) AS LinkedPostId,
    uar.UserRank AS AnswerOwnerRank,
    uar.Reputation AS AnswerOwnerReputation,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    COALESCE(ple.LastEditorDisplayName, 'N/A') AS LastEditorDisplayName,
    to_char(ple.LastEditDate, 'YYYY-MM-DD HH24:MI:SS') AS LastEditTimestamp,
    CASE
        WHEN aq.QuestionScore > aq.OverallAvgScore THEN 'Above Average Score'
        WHEN aq.QuestionScore = aq.OverallAvgScore THEN 'Average Score'
        ELSE 'Below Average Score'
    END AS ScoreComparison,
    CASE
        WHEN aq.AnswerScore IS NULL OR aq.AnswerScore < 0 THEN 'Negative or Null Answer Score'
        WHEN aq.AnswerScore = 0 THEN 'Zero Answer Score'
        ELSE 'Positive Answer Score'
    END AS AnswerScoreStatus
FROM AnsweredQuestions aq
LEFT JOIN UserActivityRanked uar ON uar.Id = aq.AnswerOwnerId
LEFT JOIN RecursiveTagHierarchy tth ON tth.TagName = ANY(aq.TagList)
LEFT JOIN TopLinkDuplicates tl ON tl.PostId = aq.QuestionId AND tl.rn = 1
LEFT JOIN PostLastEditDetails ple ON ple.PostId = aq.AnswerId
WHERE
    aq.QuestionScoreRank <= 100
    AND (aq.AnswerScore > (aq.OverallAvgScore * 0.5) OR aq.QuestionComments > 5)
GROUP BY
    aq.QuestionId,
    aq.Title,
    aq.QuestionScore,
    aq.QuestionComments,
    aq.AnswerId,
    uar.DisplayName,
    aq.AnswerScore,
    aq.AnswerComments,
    aq.AnswerCreationDate,
    aq.TagList,
    tl.LinkTypeName,
    tl.RelatedPostId,
    uar.UserRank,
    uar.Reputation,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    ple.LastEditorDisplayName,
    ple.LastEditDate,
    aq.OverallAvgScore
ORDER BY
    aq.QuestionScore DESC NULLS LAST,
    aq.AnswerScore DESC NULLS LAST,
    AggregateTagViewScore DESC NULLS LAST
LIMIT 50;
