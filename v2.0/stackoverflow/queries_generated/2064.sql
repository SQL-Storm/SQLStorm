-- {"query": "2064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1354} 

WITH RecursiveUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 100 AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
),
FilteredPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.ParentId
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score >= 5
      AND (p.Tags IS NOT NULL AND p.Tags <> '')
),
TopTagBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        COUNT(*) AS BadgeCount,
        RANK() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges b
    WHERE b.TagBased = 1
    GROUP BY b.UserId, b.Name
),
PostScoreDiff AS (
    SELECT
        p.Id,
        p.Score,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
ConsolidatedPosts AS (
    SELECT
        fp.Id,
        fp.PostTypeId,
        fp.Title,
        fp.Tags,
        fp.CreationDate,
        fp.Score,
        fp.ViewCount,
        fp.AcceptedAnswerId,
        fp.OwnerUserId,
        fp.ParentId,
        psd.PrevScore,
        psd.NextScore
    FROM FilteredPosts fp
    LEFT JOIN PostScoreDiff psd ON psd.Id = fp.Id
),
PostWithDuplicateLinks AS (
    SELECT
        cp.*,
        pl.RelatedPostId AS DuplicatePostId
    FROM ConsolidatedPosts cp
    LEFT JOIN PostLinks pl ON cp.Id = pl.PostId AND pl.LinkTypeId = 3
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.Text ILIKE '%help%' THEN 1 ELSE 0 END) AS HelpMentions
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostCloseReasons AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReason,
        MAX(ph.CreationDate) AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId, crt.Name
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ucs.TotalComments,0) AS TotalComments,
        COALESCE(ucs.AvgCommentLength,0) AS AvgCommentLength,
        COALESCE(ucs.HelpMentions,0) AS HelpMentions,
        COALESCE(tbb.BadgeName, 'None') AS TopBadge,
        COALESCE(tbb.BadgeCount, 0) AS TopBadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.Score) AS MaxPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN TopTagBadges tbb ON u.Id = tbb.UserId AND tbb.BadgeRank = 1
    GROUP BY u.Id, u.DisplayName, ucs.TotalComments, ucs.AvgCommentLength, ucs.HelpMentions, tbb.BadgeName, tbb.BadgeCount
),
PostWithRankAndPercentile AS (
    SELECT 
        pw.*,
        ROW_NUMBER() OVER (PARTITION BY pw.OwnerUserId ORDER BY pw.Score DESC) AS PostScoreRank,
        PERCENT_RANK() OVER (PARTITION BY pw.OwnerUserId ORDER BY pw.Score) AS PostScorePercentile
    FROM PostWithDuplicateLinks pw
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.TotalComments,
    uas.AvgCommentLength,
    uas.HelpMentions,
    uas.TopBadge,
    uas.TopBadgeCount,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.AveragePostScore,
    uas.MaxPostScore,
    pw.PostScoreRank,
    pw.PostScorePercentile,
    COALESCE(pcr.CloseReason, 'Not Closed') AS CloseStatus,
    CONCAT_WS(' | ',
              COALESCE(pw.Tags, '[no tags]'),
              CASE WHEN pw.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'No accepted answer' END,
              CASE WHEN pw.DuplicatePostId IS NOT NULL THEN 'Is Duplicate' ELSE 'Original Post' END,
              CASE WHEN LENGTH(pw.Title) > 100 THEN 'Long Title' ELSE 'Title OK' END,
              CASE WHEN pw.Score >= 50 THEN 'Hot' ELSE 'Normal' END
    ) AS PostSummary
FROM UserActivitySummary uas
LEFT JOIN PostWithRankAndPercentile pw ON pw.OwnerUserId = uas.UserId
LEFT JOIN PostCloseReasons pcr ON pcr.PostId = pw.Id
WHERE uas.Reputation > 500
  AND (pw.CreationDate > CURRENT_DATE - INTERVAL '1 year' OR pw.CreationDate IS NULL)
ORDER BY uas.MaxPostScore DESC NULLS LAST, uas.TotalComments DESC NULLS LAST
LIMIT 100;
