WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
    UNION ALL
    SELECT t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id = r.Id AND r.Level < 3
),
PostStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags,'') AS Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevActivity,
        LEAD(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextActivity
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, u.DisplayName, p.LastActivityDate
),
CloseReasonAggregate AS (
    SELECT
        pht.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory pht
    JOIN PostHistoryTypes phtypes ON pht.PostHistoryTypeId = phtypes.Id
    JOIN CloseReasonTypes crt ON crt.Id = CAST(pht.Comment AS INTEGER)
    WHERE pht.PostHistoryTypeId = 10
    GROUP BY pht.PostId, crt.Name
),
AnswerAggregatedStats AS (
    SELECT 
        ans.ParentId AS QuestionId,
        COUNT(ans.Id) AS AnswerCount,
        AVG(ans.Score) AS AvgAnswerScore,
        SUM(CASE WHEN ans.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
        MAX(ans.CreationDate) AS LastAnswerDate
    FROM Posts ans
    WHERE ans.PostTypeId = 2
    GROUP BY ans.ParentId
),
AcceptedAnswerDetails AS (
    SELECT
        q.Id AS QuestionId,
        acc.Id AS AcceptedAnswerId,
        acc.Score AS AcceptedAnswerScore,
        acc.CreationDate AS AcceptedAnswerDate,
        u.Reputation AS AcceptedAnswerOwnerRep,
        u.DisplayName AS AcceptedAnswerOwnerName
    FROM Posts q
    LEFT JOIN Posts acc ON acc.Id = q.AcceptedAnswerId
    LEFT JOIN Users u ON u.Id = acc.OwnerUserId
    WHERE q.PostTypeId = 1
),
PostLinkSummary AS (
    SELECT 
        pl.PostId,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks,
        SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS LinkedPostsCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        LEAD(MIN(p.CreationDate)) OVER (ORDER BY u.Reputation DESC) AS NextUserFirstPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexPredicates AS (
    SELECT
        ps.Id AS PostId,
        LENGTH(COALESCE(ps.Tags, '')) - LENGTH(REPLACE(COALESCE(ps.Tags,''), '><', '')) + 1 AS TagCount,
        CASE
            WHEN ps.Score > 10 AND ps.ViewCount > 1000 THEN 'High Impact'
            WHEN ps.Score > 0 THEN 'Positive'
            WHEN ps.Score = 0 THEN 'Neutral'
            ELSE 'Negative'
        END AS ImpactLabel,
        CASE 
            WHEN ps.OwnerUserId IS NULL THEN 'Anonymous or Deleted'
            WHEN ps.OwnerUserId <= 0 THEN 'Community Owned or System'
            ELSE 'Registered User'
        END AS OwnerStatus,
        REGEXP_REPLACE(ps.OwnerName,'[^a-zA-Z0-9]+','', 'g') AS CleanOwnerName,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id AND (c.Text ILIKE '%error%' OR c.Text ILIKE '%fail%')) AS ErrorCommentsCount,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 2) AS LastUpvoteDate,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId IN (3, 12)) AS NegativeVotes,
        GREATEST(COALESCE(ps.PrevActivity, TIMESTAMP '1900-01-01'), COALESCE(ps.NextActivity, TIMESTAMP '1900-01-01')) AS RelevantActivityDate
    FROM PostStats ps
),
FinalOutput AS (
    SELECT
        cp.PostId,
        ps.PostTypeId,
        ps.CreationDate,
        ps.Score,
        ps.ViewCount,
        cp.TagCount,
        cp.ImpactLabel,
        cp.OwnerStatus,
        cp.CleanOwnerName,
        psa.AnswerCount,
        psa.AvgAnswerScore,
        psa.HighScoreAnswers,
        ca.CloseReasonName,
        ca.CloseVotesCount,
        ald.AcceptedAnswerScore,
        ald.AcceptedAnswerOwnerRep,
        pls.DuplicateLinks,
        pls.LinkedPostsCount,
        ua.TotalPosts AS OwnerTotalPosts,
        ua.QuestionCount AS OwnerQuestions,
        ua.AnswerCount AS OwnerAnswers,
        ua.LastPostDate AS OwnerLastPost,
        ua.DisplayName AS OwnerDisplayName,
        (CASE WHEN ps.Score < 0 AND cp.ErrorCommentsCount = 0 THEN 1 ELSE 0 END) AS PossibleFalseNegative
    FROM ComplexPredicates cp
    JOIN PostStats ps ON ps.Id = cp.PostId
    LEFT JOIN AnswerAggregatedStats psa ON psa.QuestionId = ps.Id
    LEFT JOIN CloseReasonAggregate ca ON ca.PostId = ps.Id
    LEFT JOIN AcceptedAnswerDetails ald ON ald.QuestionId = ps.Id
    LEFT JOIN PostLinkSummary pls ON pls.PostId = ps.Id
    LEFT JOIN UserActivityWindow ua ON ua.UserId = ps.OwnerUserId
)
SELECT DISTINCT
    fo.PostId,
    fo.PostTypeId,
    fo.CreationDate,
    fo.Score,
    fo.ViewCount,
    fo.TagCount,
    fo.ImpactLabel,
    fo.OwnerStatus,
    fo.CleanOwnerName,
    fo.AnswerCount,
    ROUND(COALESCE(fo.AvgAnswerScore,0)::double precision::numeric,2) AS AvgAnswerScore,
    fo.HighScoreAnswers,
    COALESCE(fo.CloseReasonName,'Not Closed') AS CloseReasonName,
    COALESCE(fo.CloseVotesCount,0) AS CloseVotesCount,
    fo.AcceptedAnswerScore,
    fo.AcceptedAnswerOwnerRep,
    COALESCE(fo.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(fo.LinkedPostsCount,0) AS LinkedPostsCount,
    fo.OwnerTotalPosts,
    fo.OwnerQuestions,
    fo.OwnerAnswers,
    fo.OwnerLastPost,
    fo.OwnerDisplayName,
    fo.PossibleFalseNegative
FROM FinalOutput fo
WHERE fo.PostTypeId = 1
  AND (fo.ViewCount > 1000 OR fo.Score >= 10)
  AND (fo.CloseVotesCount IS NULL OR fo.CloseVotesCount < 5)
ORDER BY fo.ViewCount DESC, fo.Score DESC
LIMIT 100;