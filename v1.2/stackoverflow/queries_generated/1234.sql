-- {"query": "1234.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1777} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, 1 AS Level, t.Count, t.ExcerptPostId
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT t2.Id, t2.TagName, rh.Level + 1, t2.Count, t2.ExcerptPostId
    FROM Tags t2
    JOIN RecursiveTagHierarchy rh ON t2.TagName LIKE rh.TagName || '%'
    WHERE t2.IsRequired = 0 AND rh.Level < 3
),
PostWithVotesAndComments AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END),0) AS UpVotes,
        COALESCE(SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END),0) AS DownVotes,
        COALESCE(c.CommentCount, 0) AS TotalComments,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, c.CommentCount
),
UserBadgeAggregation AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        JSON_AGG(DISTINCT b.Name) FILTER (WHERE b.Date > NOW() - INTERVAL '6 months') AS RecentBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
AcceptedAnswerCandidates AS (
    SELECT
        p.Id AS QuestionId,
        p.AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.OwnerUserId AS AcceptedAnswerOwner,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY a.Score DESC NULLS LAST) AS RankWithinAccepted
    FROM Posts p
    LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
),
DuplicateQuestionsWithCloseInfo AS (
    SELECT DISTINCT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
    LEFT JOIN PostHistory ph ON ph.PostId = pl.PostId AND ph.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE pl.PostId IS NOT NULL AND pl.RelatedPostId IS NOT NULL
),
WindowedUserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS UserQuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS UserAnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        RANK() OVER(ORDER BY AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) DESC) AS UserRankByAvgAnswerScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
CorrelatedPostHistory AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        ph1.Text AS InitialTitle,
        ph2.Text AS LatestEditBody,
        ph_close.CreationDate AS ClosingDate,
        ph_close.Comment AS CloseReasonIdJson,
        (SELECT COUNT(DISTINCT phsub.UserId) 
         FROM PostHistory phsub 
         WHERE phsub.PostId = p.Id AND phsub.UserId IS NOT NULL) AS DistinctEditorsCount
    FROM Posts p
    LEFT JOIN PostHistory ph1 ON ph1.PostId = p.Id AND ph1.PostHistoryTypeId = 1 -- Initial Title
    LEFT JOIN PostHistory ph2 ON ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 5 -- Edit Body
    LEFT JOIN PostHistory ph_close ON ph_close.PostId = p.Id AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '2 years'
)
SELECT 
    pwv.Id AS PostId,
    pwv.PostTypeId,
    COALESCE(u.DisplayName, 'Anonymous') AS OwnerName,
    pwv.Title,
    pwv.CreationDate,
    pwv.Score,
    pwv.ViewCount,
    pwv.Tags,
    pwv.UpVotes,
    pwv.DownVotes,
    pwv.TotalComments,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.RecentBadges,
    rh.InitialTitle,
    SUBSTRING(rh.LatestEditBody, 1, 200) AS LatestEditBodySnippet,
    rh.ClosingDate,
    crt.Name AS CloseReasonName,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    dup.CloseDate AS DuplicateCloseDate,
    dup.CloseReason,
    wc.UserQuestionCount,
    wc.UserAnswerCount,
    wc.AvgAnswerScore,
    wc.UserRankByAvgAnswerScore,
    pwv.ScoreRank,
    rh.DistinctEditorsCount,
    /* Complex condition mixing NULL logic and string operations */
    CASE 
        WHEN pwv.Tags IS NULL THEN 'No Tags'
        WHEN pwv.Tags LIKE '%<sql>%' OR pwv.Tags LIKE '%<plsql>%' THEN 'Related to SQL/PLSQL'
        WHEN POSITION('database' IN LOWER(pwv.Title)) > 0 THEN 'Contains database Keyword'
        WHEN LENGTH(pwv.Title) > 100 THEN 'Long Title'
        ELSE 'Other'
    END AS PostCategory
FROM PostWithVotesAndComments pwv
LEFT JOIN UserBadgeAggregation uba ON uba.UserId = pwv.OwnerUserId
LEFT JOIN CorrelatedPostHistory rh ON rh.PostId = pwv.Id
LEFT JOIN DuplicateQuestionsWithCloseInfo dup ON dup.DuplicateQuestionId = pwv.Id
LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(rh.CloseReasonIdJson AS SMALLINT)
LEFT JOIN WindowedUserPostStats wc ON wc.OwnerUserId = pwv.OwnerUserId

WHERE 
    pwv.ScoreRank <= 50
    AND (uba.GoldBadges > 0 OR uba.SilverBadges > 3) 
    AND (pwv.CreationDate < NOW() - INTERVAL '1 month' OR pwv.CreationDate IS NULL)

ORDER BY pwv.ScoreRank, pwv.CreationDate DESC

UNION

SELECT 
    p.Id, 
    p.PostTypeId,
    u.DisplayName,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    0,
    0,
    0,
    0,
    0,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Fallback'
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1 AND p.Score IS NULL

ORDER BY 1 DESC
LIMIT 100;
