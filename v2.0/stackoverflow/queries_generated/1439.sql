-- {"query": "1439.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3699} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreGivenOrReceived,
        MAX(GREATEST(
            COALESCE(p.LastActivityDate, p.CreationDate, '1900-01-01'::timestamp),
            COALESCE(c.CreationDate, '1900-01-01'::timestamp),
            COALESCE(u.LastAccessDate, '1900-01-01'::timestamp)
        )) AS LastUserActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostTagAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))) AS TagName,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastActivityDate,
        p.ClosedDate
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
MonthlyTagPerformance AS (
    SELECT
        EXTRACT(YEAR FROM pta.PostCreationDate) AS Year,
        EXTRACT(MONTH FROM pta.PostCreationDate) AS Month,
        pta.TagName,
        COUNT(DISTINCT pta.PostId) AS MonthlyTaggedPostCount,
        COALESCE(AVG(pta.PostScore), 0) AS AvgMonthlyTagScore,
        COUNT(DISTINCT pta.OwnerUserId) AS MonthlyUniqueTagUsers
    FROM PostTagAggregates pta
    GROUP BY 1, 2, pta.TagName
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount, -- Edit Title, Body, Tags
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedByHistoryDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id END) AS CommunityOwnedCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 3 THEN ph.Id END) AS InitialTagHistoryCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
CommentSummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalCommentsOnPost,
        SUM(c.Score) AS TotalCommentScoreOnPost,
        MAX(c.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT c.UserId) AS UniqueCommentersOnPost
    FROM Comments c
    GROUP BY c.PostId
),
PostEngagementEvents AS ( -- This CTE uses a FULL OUTER JOIN
    SELECT
        COALESCE(phd.PostId, cs.PostId) AS PostId,
        phd.EditCount,
        phd.FirstEditDate,
        phd.LastEditDate,
        phd.ClosedByHistoryDate,
        phd.ReopenedDate,
        phd.CommunityOwnedCount,
        phd.InitialTagHistoryCount,
        cs.TotalCommentsOnPost,
        cs.TotalCommentScoreOnPost,
        cs.LatestCommentDate,
        cs.UniqueCommentersOnPost
    FROM PostHistoryDetails phd
    FULL OUTER JOIN CommentSummary cs ON phd.PostId = cs.PostId
),
LinkedPostScores AS (
    SELECT
        pl.PostId,
        COALESCE(AVG(p_related.Score), 0) AS AvgRelatedPostScore,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount
    FROM PostLinks pl
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    GROUP BY pl.PostId
),
FinalPostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount AS PostTableCommentCount, -- Original comment count from Posts table
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        pee.EditCount,
        pee.FirstEditDate,
        pee.LastEditDate,
        pee.ClosedByHistoryDate,
        pee.ReopenedDate,
        pee.CommunityOwnedCount,
        pee.InitialTagHistoryCount,
        COALESCE(pee.TotalCommentsOnPost, 0) AS TotalCommentsFromHistory, -- Comments from CommentSummary
        COALESCE(pee.TotalCommentScoreOnPost, 0) AS TotalCommentScoreFromHistory,
        COALESCE(pee.LatestCommentDate, '1900-01-01'::timestamp) AS LatestCommentDate,
        COALESCE(pee.UniqueCommentersOnPost, 0) AS UniqueCommentersOnPost,
        COALESCE(lps.AvgRelatedPostScore, 0) AS AvgRelatedPostScore,
        COALESCE(lps.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(lps.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        -- Complex calculation and NULL handling for acceptance rate, only for questions
        NULLIF(
            CAST(
                SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId)
            ) * 1.0 /
            NULLIF(
                SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId),
                0
            ),
            0
        ) AS OwnerQuestionAcceptanceRate,
        -- Window function: Rank posts by score within each post type and year
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId, EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC, p.CreationDate) AS PostScoreRankByYearAndType,
        -- Window function: NTILE for distribution of view counts
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) AS ViewCountPercentileTile,
        -- String processing for tags, assuming Tags column is '><tag1><tag2>'
        LOWER(SUBSTRING(p.Tags, 2, POSITION('><' IN p.Tags || '><') - 2)) AS FirstTag, -- Get the first tag
        -- Correlated subquery to check if there is an answer with a score higher than the question itself
        EXISTS (SELECT 1 FROM Posts ans WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2 AND ans.Score > p.Score) AS HasHigherScoringAnswer
    FROM Posts p
    LEFT JOIN PostEngagementEvents pee ON p.Id = pee.PostId -- Use the CTE with FULL OUTER JOIN results
    LEFT JOIN LinkedPostScores lps ON p.Id = lps.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
)
SELECT
    fpm.PostId,
    fpm.PostTypeId,
    fpm.Title,
    fpm.PostCreationDate,
    fpm.Score AS PostScore,
    fpm.ViewCount,
    fpm.OwnerUserId,
    uas.DisplayName AS OwnerDisplayName,
    uas.Reputation AS OwnerReputation,
    uas.TotalQuestions AS OwnerTotalQuestions,
    uas.TotalAnswers AS OwnerTotalAnswers,
    fpm.AnswerCount,
    fpm.PostTableCommentCount, -- Original comment count from Posts table
    fpm.TotalCommentsFromHistory, -- Total comments derived from CommentSummary CTE
    fpm.TotalCommentScoreFromHistory,
    fpm.UniqueCommentersOnPost,
    fpm.FavoriteCount,
    fpm.ClosedDate,
    fpm.LastActivityDate,
    fpm.EditCount,
    fpm.FirstEditDate,
    fpm.LastEditDate,
    fpm.ClosedByHistoryDate,
    fpm.ReopenedDate,
    fpm.CommunityOwnedCount,
    fpm.AvgRelatedPostScore,
    fpm.LinkedPostsCount,
    fpm.DuplicatePostsCount,
    fpm.OwnerQuestionAcceptanceRate,
    fpm.PostScoreRankByYearAndType,
    fpm.ViewCountPercentileTile,
    fpm.FirstTag,
    fpm.HasHigherScoringAnswer,
    mtp.TagName AS MonthlyTopTag,
    mtp.MonthlyTaggedPostCount,
    mtp.AvgMonthlyTagScore,
    mtp.MonthlyUniqueTagUsers,
    -- Lag/Lead window functions for user's post activity
    LAG(fpm.PostCreationDate, 1, fpm.PostCreationDate) OVER (PARTITION BY fpm.OwnerUserId ORDER BY fpm.PostCreationDate) AS PrevPostCreationDate,
    LEAD(fpm.PostCreationDate, 1, fpm.PostCreationDate) OVER (PARTITION BY fpm.OwnerUserId ORDER BY fpm.PostCreationDate) AS NextPostCreationDate,
    -- Complicated expression combining user reputation, post score, view count, badge count, and comment data
    (
        COALESCE(fpm.Score, 0) * 0.7
        + COALESCE(fpm.ViewCount, 0) * 0.05
        + COALESCE(fpm.AnswerCount, 0) * 0.8
        + COALESCE(fpm.TotalCommentsFromHistory, 0) * 0.15 -- Use derived comment count
        + COALESCE(fpm.TotalCommentScoreFromHistory, 0) * 0.05 -- Use derived comment score
        + COALESCE(fpm.FavoriteCount, 0) * 0.5
        + COALESCE(fpm.AvgRelatedPostScore, 0) * 0.3
        + COALESCE(uas.Reputation, 0) * 0.0001
        + CASE WHEN fpm.PostTypeId = 1 AND fpm.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END
        + (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 1) * 5 -- Gold badges bonus
        - (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = fpm.PostId AND v.VoteTypeId = 3) * 2 -- Downvote penalty (from Votes table)
        + COALESCE(
            (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = fpm.PostId AND v.VoteTypeId = 8),
            0
        ) * 0.2 -- Bounty contribution
    ) AS CalculatedEngagementScore,
    -- String manipulation with NULL handling and conditional formatting
    REPLACE(
        LOWER(COALESCE(fpm.Title, 'NO_TITLE_AVAILABLE')),
        ' ', '-'
    ) || '-' ||
    CASE
        WHEN fpm.PostTypeId = 1 THEN 'Q'
        WHEN fpm.PostTypeId = 2 THEN 'A'
        ELSE 'OTHER'
    END || '-' ||
    TRIM(LEADING '0' FROM LPAD(CAST(fpm.PostId AS VARCHAR), 10, '0')) ||
    (CASE WHEN fpm.Title ILIKE '%performance%' OR fpm.Title ILIKE '%optimize%' THEN '-PERF_TOPIC' ELSE '' END)
    AS UniquePostSlugWithTopicHint,
    -- NULL logic: Check if a post was edited more than 5 times and never closed (or reopened)
    CASE
        WHEN COALESCE(fpm.EditCount, 0) > 5 AND fpm.ClosedDate IS NULL AND fpm.ReopenedDate IS NULL THEN 'HighlyEditedOpen'
        WHEN COALESCE(fpm.EditCount, 0) > 0 AND fpm.ClosedDate IS NOT NULL AND fpm.ReopenedDate IS NULL THEN 'EditedAndClosed'
        WHEN COALESCE(fpm.EditCount, 0) > 0 AND fpm.ClosedDate IS NOT NULL AND fpm.ReopenedDate IS NOT NULL AND fpm.ReopenedDate > fpm.ClosedDate THEN 'EditedReopened'
        WHEN COALESCE(fpm.EditCount, 0) = 0 AND fpm.ClosedDate IS NULL THEN 'OriginalOpen'
        ELSE 'OtherStatus'
    END AS PostStatusCategory
FROM FinalPostMetrics fpm
LEFT JOIN UserActivitySummary uas ON fpm.OwnerUserId = uas.UserId
LEFT JOIN MonthlyTagPerformance mtp ON
    fpm.FirstTag = mtp.TagName
    AND EXTRACT(YEAR FROM fpm.PostCreationDate) = mtp.Year
    AND EXTRACT(MONTH FROM fpm.PostCreationDate) = mtp.Month
WHERE
    fpm.OwnerUserId IS NOT NULL -- Exclude posts by community user etc.
    AND fpm.Score >= 0 -- Only positive or zero score posts
    AND fpm.PostCreationDate BETWEEN '2020-01-01' AND '2023-01-01' -- Date range for performance
    AND uas.Reputation > 1000 -- Filter by more reputable users
    AND fpm.ViewCount >= COALESCE((SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate BETWEEN '2020-01-01' AND '2023-01-01'), 0) -- Above average views for questions, handle NULL avg
    -- Correlated subquery to check for at least one vote of type 2 (UpMod)
    AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = fpm.PostId AND v.VoteTypeId = 2)
    -- More complex predicate using date math and comparison, and NULL logic
    AND (
        fpm.LastActivityDate IS NULL
        OR (fpm.LastActivityDate - fpm.PostCreationDate) < INTERVAL '365 days'
        OR COALESCE(fpm.EditCount, 0) > 2
    )
ORDER BY
    CalculatedEngagementScore DESC,
    fpm.PostCreationDate DESC,
    fpm.PostId
LIMIT 5000;
