-- {"query": "1218.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3700} 

WITH UserActivitySummary AS (
    -- Summarizes user engagement metrics, including post counts by type, comment counts, vote counts, and badge counts.
    -- Uses LEFT JOINs to ensure all users are considered, even if they have no related activities.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        DATE_PART('day', AGE(u.LastAccessDate, u.CreationDate)) AS DaysActive, -- Calculates user activity duration in days.
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS QuestionWithAcceptedAnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END), 0) AS AcceptedAnswersGivenCount,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGiven,
        COALESCE(SUM(CASE WHEN p.OwnerUserId = u.Id AND pv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS ReceivedUpvotesOnPosts,
        COALESCE(SUM(CASE WHEN p.OwnerUserId = u.Id AND pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS ReceivedDownvotesOnPosts,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts q ON p.PostTypeId = 1 AND q.Id = p.ParentId -- Links answers to their parent questions to check for accepted answers
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Votes pv ON p.Id = pv.PostId AND p.OwnerUserId = u.Id -- Captures votes specifically on posts owned by the user
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostHistoricalAnalysis AS (
    -- Analyzes the lifecycle of posts by tracking historical changes, edit dates, and closure/reopening events.
    -- Includes a correlated subquery to fetch the owner's reputation at post creation.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditDate,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS FirstEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS ReopenedDate,
        (SELECT u_owner.Reputation FROM Users u_owner WHERE u_owner.Id = p.OwnerUserId LIMIT 1) AS OwnerReputationAtPostCreation -- Correlated subquery
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.AnswerCount, p.OwnerUserId
),
NormalizedPostTags AS (
    -- Parses the 'Tags' string column from Posts into individual tag rows using string_to_array and UNNEST.
    SELECT
        p.Id AS PostId,
        TRIM(tag_val) AS TagName
    FROM
        Posts p,
        UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag_val
    WHERE
        p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
TagPerformanceMetrics AS (
    -- Aggregates performance metrics for each tag, including total posts, average score, and the most frequent owner.
    -- Contains a correlated subquery to identify the most frequent owner for a given tag.
    SELECT
        npt.TagName,
        COUNT(DISTINCT npt.PostId) AS TaggedPostCount,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.Score) AS AvgTagScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN npt.PostId ELSE NULL END) AS QuestionCountByTag,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN npt.PostId ELSE NULL END) AS AnswerCountByTag,
        (SELECT u_freq.DisplayName -- Correlated subquery to find the most frequent tag owner
         FROM Posts p_inner
         JOIN NormalizedPostTags npt_inner ON p_inner.Id = npt_inner.PostId
         JOIN Users u_freq ON p_inner.OwnerUserId = u_freq.Id
         WHERE npt_inner.TagName = npt.TagName
         GROUP BY u_freq.DisplayName
         ORDER BY COUNT(p_inner.Id) DESC
         LIMIT 1
        ) AS MostFrequentTagOwnerDisplayName
    FROM
        NormalizedPostTags npt
    JOIN Posts p ON npt.PostId = p.Id
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        npt.TagName
    HAVING
        COUNT(DISTINCT npt.PostId) > 100 -- Filters for tags with substantial usage
),
DuplicatePostChains AS (
    -- Identifies duplicate posts using PostLinks and ranks them to find the most recent duplicate link.
    SELECT
        pl.PostId AS OriginalPostId,
        pl.RelatedPostId AS DuplicateOfPostId,
        p.Title AS OriginalPostTitle,
        pr.Title AS DuplicateOfPostTitle,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn_duplicate -- Window function for ranking
    FROM
        PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts pr ON pl.RelatedPostId = pr.Id
    WHERE
        pl.LinkTypeId = 3 -- Specifically for duplicate links
),
ModeratorActivitySnapshots AS (
    -- Captures specific moderator actions on posts (close, reopen, lock, unlock, protect, unprotect)
    -- Uses LAG and LEAD window functions to analyze sequential events, e.g., time between close and reopen.
    SELECT
        ph.PostId,
        ph.CreationDate AS ActionDate,
        ph.UserId AS ModeratorId,
        u.DisplayName AS ModeratorDisplayName,
        ph.PostHistoryTypeId AS ActionTypeId,
        pht.Name AS ActionTypeName,
        LAG(ph.PostHistoryTypeId, 1, 0) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousActionTypeId,
        LEAD(ph.CreationDate, 1, '9999-12-31') OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextActionDate,
        CASE -- Complex calculation involving LAG/LEAD and date difference
            WHEN ph.PostHistoryTypeId = 10 AND LEAD(ph.PostHistoryTypeId, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) = 11
            THEN DATE_PART('hour', LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) - ph.CreationDate)
            ELSE NULL
        END AS HoursUntilReopenedAfterClose
    FROM
        PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE
        ph.PostHistoryTypeId IN (10, 11, 14, 15, 19, 20) -- Relevant moderator action types
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.DaysActive,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.AcceptedAnswersGivenCount,
    uas.CommentCount,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    -- Custom "User Engagement Score" calculation with weighted factors.
    (uas.QuestionCount * 5 + uas.AnswerCount * 3 + uas.AcceptedAnswersGivenCount * 10 + uas.CommentCount + uas.ReceivedUpvotesOnPosts * 2 + uas.GoldBadges * 50 + uas.SilverBadges * 20 + uas.BronzeBadges * 5) AS UserEngagementScore,
    -- Ranks users based on their engagement score using DENSE_RANK.
    DENSE_RANK() OVER (ORDER BY (uas.QuestionCount * 5 + uas.AnswerCount * 3 + uas.AcceptedAnswersGivenCount * 10 + uas.CommentCount + uas.ReceivedUpvotesOnPosts * 2 + uas.GoldBadges * 50 + uas.SilverBadges * 20 + uas.BronzeBadges * 5) DESC) AS UserEngagementRank,

    p.Id AS PostId, -- Joining with 'Posts' table directly to get post-specific details
    pha.PostTypeId,
    pha.PostCreationDate,
    pha.Score AS PostScore,
    pha.ViewCount AS PostViewCount,
    pha.AnswerCount AS PostAnswerCount,
    pha.TotalHistoryEntries,
    pha.FirstEditDate,
    pha.LastEditDate,
    pha.ClosedDate,
    pha.ReopenedDate,
    COALESCE(DATE_PART('day', AGE(pha.LastEditDate, pha.FirstEditDate)), 0) AS DaysBetweenFirstAndLastEdit,
    CASE -- Calculates days until the first edit, handles NULLs
        WHEN pha.FirstEditDate IS NOT NULL THEN
            DATE_PART('day', AGE(pha.FirstEditDate, pha.PostCreationDate))
        ELSE NULL
    END AS DaysToFirstEdit,
    pha.OwnerReputationAtPostCreation,

    npt.TagName, -- Individual tag associated with the post
    tpm.TaggedPostCount,
    tpm.AvgTagScore,
    tpm.MostFrequentTagOwnerDisplayName,

    dpc.DuplicateOfPostId,
    dpc.DuplicateOfPostTitle,
    -- String manipulations with NULL logic: Uppercase prefix of title, lowercase and replaced spaces in body snippet.
    UPPER(LEFT(COALESCE(p.Title, 'NO_TITLE_AVAILABLE'), 20)) AS PostTitlePrefix,
    LOWER(REPLACE(SUBSTRING(p.Body, 1, 100), ' ', '_')) AS PostBodySlugFragment,
    
    mas.ModeratorDisplayName,
    mas.ActionTypeName,
    mas.HoursUntilReopenedAfterClose,
    NTILE(5) OVER (ORDER BY pha.ViewCount DESC, pha.Score DESC) AS ViewScoreQuartile, -- Divides posts into 5 performance groups based on views and score

    (SELECT SUM(s.Score) FROM Comments s WHERE s.PostId = p.Id) AS TotalCommentScore, -- Scalar subquery for total comment score
    
    p.FavoriteCount,
    CASE -- Complex NULL logic and conditional expression for post status
        WHEN p.ClosedDate IS NOT NULL AND p.ReopenedDate IS NULL THEN 'Closed'
        WHEN p.ReopenedDate IS NOT NULL THEN 'Reopened'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
        ELSE 'Active'
    END AS PostStatusCategory
FROM
    UserActivitySummary uas
INNER JOIN Posts p ON uas.UserId = p.OwnerUserId -- Joins user summary to posts owned by them
LEFT JOIN PostHistoricalAnalysis pha ON p.Id = pha.PostId
LEFT JOIN NormalizedPostTags npt ON p.Id = npt.PostId -- Joins to individual tags for each post
LEFT JOIN TagPerformanceMetrics tpm ON npt.TagName = tpm.TagName
LEFT JOIN DuplicatePostChains dpc ON p.Id = dpc.OriginalPostId AND dpc.rn_duplicate = 1 -- Filters for the most recent duplicate link
LEFT JOIN ModeratorActivitySnapshots mas ON p.Id = mas.PostId AND mas.ActionTypeId = 10 -- Only considers close actions
WHERE
    uas.Reputation > 15000 -- Filters for high-reputation users
    AND pha.PostCreationDate BETWEEN '2021-01-01' AND '2023-06-30' -- Date range for posts
    AND (p.ViewCount > 7500 OR p.Score > 75) -- Filters for highly engaged posts
    AND (npt.TagName IN ('sql', 'postgresql', 'database', 'performance')) -- Filters for specific technology tags
    AND (p.ClosedDate IS NULL OR p.ReopenedDate IS NOT NULL) -- Posts that are not permanently closed
    AND uas.AnswerCount > uas.QuestionCount * 0.75 -- Users who answer significantly more than they ask
    AND uas.GoldBadges > 0 -- Users with at least one gold badge
GROUP BY -- Extensive GROUP BY to retain all selected details after multiple joins
    uas.UserId, uas.DisplayName, uas.Reputation, uas.DaysActive, uas.QuestionCount, uas.AnswerCount, uas.AcceptedAnswersGivenCount,
    uas.CommentCount, uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges,
    p.Id, p.Title, p.Body, p.FavoriteCount, p.ClosedDate, p.ReopenedDate, p.CommunityOwnedDate,
    pha.PostTypeId, pha.PostCreationDate, pha.Score, pha.ViewCount, pha.AnswerCount,
    pha.TotalHistoryEntries, pha.FirstEditDate, pha.LastEditDate, pha.ClosedDate, pha.ReopenedDate, pha.OwnerReputationAtPostCreation,
    npt.TagName, tpm.TaggedPostCount, tpm.AvgTagScore, tpm.MostFrequentTagOwnerDisplayName,
    dpc.DuplicateOfPostId, dpc.DuplicateOfPostTitle,
    mas.ModeratorDisplayName, mas.ActionTypeName, mas.HoursUntilReopenedAfterClose
HAVING
    COUNT(DISTINCT p.Id) > 5 -- Filters out user-tag combinations with fewer than 5 posts
ORDER BY
    uas.UserEngagementRank ASC,
    pha.Score DESC,
    pha.ViewCount DESC,
    pha.LastActivityDate DESC
LIMIT 1000;
