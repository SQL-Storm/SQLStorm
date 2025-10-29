-- {"query": "1546.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2363} 

WITH UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven, -- Votes made by this user on any post
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven, -- Votes made by this user on any post
        AVG(u.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AvgReputationForCohort
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Title,
        p.Tags,
        p.Score AS InitialScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesOnPost, -- Upvotes received by this post
        SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesOnPost, -- Downvotes received by this post
        COUNT(DISTINCT c.Id) AS TotalCommentsOnPost,
        COUNT(DISTINCT c.UserId) AS DistinctCommentersOnPost,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByUserPostScore,
        -- Extract the first tag for potential join and display
        TRIM(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1)) AS PrimaryTag
    FROM Posts p
    LEFT JOIN Votes pv ON p.Id = pv.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.CommentCount, p.LastEditDate, p.LastActivityDate, p.ClosedDate
),
PostEditActivity AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEdits, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) AS TotalRollbacks, -- Rollback Title, Body, Tags
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS FirstEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit or Rollback types
    GROUP BY ph.PostId
),
TagPerformance AS (
    -- This CTE calculates metrics for *all* tags associated with posts
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS TotalTagPosts,
        AVG(p.ViewCount) AS AvgTagViewCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only questions contribute to tag view count/score
    GROUP BY TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
),
PotentialDuplicates AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
    GROUP BY pl.PostId
)
-- Main Query
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.LastAccessDate,
    ua.TotalBadges,
    ua.AvgReputationForCohort,
    pd.PostId,
    pd.Title,
    pd.PrimaryTag,
    pd.PostCreationDate,
    pd.InitialScore AS PostInitialScore,
    pd.ViewCount,
    pd.AnswerCount,
    pd.FavoriteCount,
    pd.CommentCount,
    pd.TotalUpVotesOnPost,
    pd.TotalDownVotesOnPost,
    pd.DistinctCommentersOnPost,
    COALESCE(pea.TotalEdits, 0) AS PostTotalEdits,
    COALESCE(pea.TotalRollbacks, 0) AS PostTotalRollbacks,
    EXTRACT(EPOCH FROM (pd.LastActivityDate - pd.PostCreationDate)) / 3600 AS HoursSinceCreationToLastActivity, -- In hours
    (CAST(pd.TotalDownVotesOnPost AS DECIMAL) / NULLIF(pd.TotalUpVotesOnPost + pd.TotalDownVotesOnPost, 0)) AS DownvoteRatio,
    (SELECT COUNT(DISTINCT ph_inner.UserId)
     FROM PostHistory ph_inner
     WHERE ph_inner.PostId = pd.PostId AND ph_inner.PostHistoryTypeId IN (4, 5, 6) AND ph_inner.UserId IS NOT NULL) AS NumberOfUniqueEditors, -- Correlated Subquery
    tp.TotalTagScore,
    tp.TotalTagPosts,
    tp.AvgTagViewCount,
    CASE
        WHEN pd.ClosedDate IS NOT NULL AND pd.PostTypeId = 1 THEN 'Closed Question'
        WHEN pd.TotalDownVotesOnPost > (pd.TotalUpVotesOnPost * 0.75) THEN 'Highly Controversial'
        WHEN pd.ViewCount > 50000 AND pd.AnswerCount > 10 THEN 'Highly Engaged'
        WHEN pd.FavoriteCount IS NOT NULL AND pd.FavoriteCount > 50 THEN 'Community Favorite'
        WHEN pd.CommentCount > 20 AND COALESCE(pea.TotalEdits, 0) > 3 THEN 'Actively Discussed & Evolving'
        ELSE 'Standard Activity'
    END AS PostCategory,
    COALESCE(dup.DuplicateCount, 0) AS TimesMarkedAsDuplicate,
    NTH_VALUE(pd.Title, 1) OVER (PARTITION BY ua.UserId ORDER BY pd.PostCreationDate ASC) AS FirstPostTitleByThisUser,
    LEAD(pd.PostCreationDate, 1) OVER (PARTITION BY ua.UserId ORDER BY pd.PostCreationDate ASC) AS NextPostCreationDate,
    SUM(pd.TotalUpVotesOnPost) OVER (PARTITION BY ua.UserId ORDER BY pd.PostCreationDate) AS RunningSumUpvotesByUser,
    RANK() OVER (PARTITION BY pd.PrimaryTag ORDER BY pd.TotalUpVotesOnPost DESC, pd.ViewCount DESC) AS RankInPrimaryTag,
    LOWER(SUBSTRING(ua.DisplayName, 1, 1)) || LENGTH(COALESCE(ua.Location, '')) || UPPER(SUBSTRING(ua.DisplayName, LENGTH(ua.DisplayName), 1)) AS UserHashKey,
    (SELECT AVG(LENGTH(c_inner.Text)) FROM Comments c_inner WHERE c_inner.PostId = pd.PostId AND c_inner.Text IS NOT NULL) AS AverageCommentLength, -- Another correlated subquery
    CAST(EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM ua.UserCreationDate) AS INT) AS UserAgeInYears,
    CAST(EXTRACT(MONTH FROM pd.PostCreationDate) AS VARCHAR(2)) || '-' || LPAD(CAST(EXTRACT(DAY FROM pd.PostCreationDate) AS VARCHAR(2)), 2, '0') AS PostDayMonth
FROM UserAggregates ua
INNER JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
LEFT JOIN PostEditActivity pea ON pd.PostId = pea.PostId
LEFT JOIN TagPerformance tp ON pd.PrimaryTag = tp.TagName
LEFT JOIN PotentialDuplicates dup ON pd.PostId = dup.PostId
WHERE
    ua.Reputation > ua.AvgReputationForCohort * 2.0
    AND ua.TotalBadges >= 10
    AND pd.RankByUserPostScore <= 5
    AND pd.PostTypeId = 1
    AND (pd.ClosedDate IS NULL OR COALESCE(pea.TotalEdits, 0) > 5)
    AND (pd.Title IS NOT NULL AND LENGTH(TRIM(pd.Title)) > 20 AND pd.Title ~ '[a-zA-Z0-9]')
    AND pd.PrimaryTag IS NOT NULL
    AND COALESCE(dup.DuplicateCount, 0) < 3
    AND (pd.InitialScore + COALESCE(pd.FavoriteCount, 0)) > 50
    AND pd.OwnerUserId IS NOT NULL
    AND pd.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
    AND COALESCE(ua.TotalDownVotesGiven, 0) < 100
ORDER BY
    ua.Reputation DESC,
    DownvoteRatio DESC,
    PostTotalEdits DESC,
    HoursSinceCreationToLastActivity DESC
LIMIT 5000;
