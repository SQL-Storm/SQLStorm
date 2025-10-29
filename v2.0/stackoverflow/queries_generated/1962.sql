-- {"query": "1962.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2591} 
WITH UserActivityStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViewsGenerated,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreAccumulated,
        COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0.0) AS AvgPostScoreReceived,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL), 0.0) AS AvgCommentScoreReceived,
        SUM(CASE WHEN p_accepted.Id IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        MAX(b.Date) AS LatestBadgeDate,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p_accepted ON p.Id = p_accepted.AcceptedAnswerId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS DirectCommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.LastActivityDate,
        p.ClosedDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.UserId END) AS DistinctFavoritingUsers,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditRevisionCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
                 ELSE NULL END) AS LastClosureStateChange,
        (SELECT crt.Name FROM PostHistory ph_close
         JOIN CloseReasonTypes crt ON crt.Id = CAST(ph_close.Comment AS smallint)
         WHERE ph_close.PostId = p.Id AND ph_close.PostHistoryTypeId = 10 AND ph_close.Comment IS NOT NULL
         ORDER BY ph_close.CreationDate ASC
         LIMIT 1) AS InitialCloseReason,
        (SELECT u_lc.DisplayName
         FROM Comments c_latest
         JOIN Users u_lc ON c_latest.UserId = u_lc.Id
         WHERE c_latest.PostId = p.Id
         ORDER BY c_latest.CreationDate DESC
         LIMIT 1) AS LatestCommenterDisplayName,
        (SELECT u_lc.Reputation
         FROM Comments c_latest
         JOIN Users u_lc ON c_latest.UserId = u_lc.Id
         WHERE c_latest.PostId = p.Id
         ORDER BY c_latest.CreationDate DESC
         LIMIT 1) AS LatestCommenterReputation,
        MAX(CASE WHEN p.ParentId IS NOT NULL THEN (SELECT q.Score FROM Posts q WHERE q.Id = p.ParentId) ELSE NULL END) AS ParentQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN (SELECT a.Score FROM Posts a WHERE a.Id = p.AcceptedAnswerId) ELSE NULL END) AS AcceptedAnswerScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY p.Id, p.PostTypeId, p.Title, p.Body, p.CreationDate, p.Score, p.ViewCount,
             p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId,
             p.LastActivityDate, p.ClosedDate
),
TagPerformanceMetrics AS (
    SELECT
        pta.PostId,
        pta.TagName,
        t.Count AS GlobalTagUsageCount,
        t.IsModeratorOnly,
        ROW_NUMBER() OVER (PARTITION BY pta.PostId ORDER BY t.Count DESC, t.TagName) AS TagOrderForPost
    FROM Posts p_tags
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p_tags.Tags, 2, length(p_tags.Tags)-2), '><')) AS TagName
        WHERE p_tags.Tags IS NOT NULL AND LENGTH(p_tags.Tags) > 2
    ) AS pta ON TRUE
    JOIN Tags t ON pta.TagName = t.TagName
    WHERE p_tags.PostTypeId = 1 -- Only questions have direct tags in Posts.Tags
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount, -- Duplicate links
        MAX(p_rel.Score) AS MaxRelatedPostScore,
        MIN(p_rel.ViewCount) AS MinRelatedPostViewCount
    FROM PostLinks pl
    JOIN Posts p_rel ON pl.RelatedPostId = p_rel.Id
    GROUP BY pl.PostId
)
SELECT
    uas.DisplayName AS UserDisplayName,
    uas.Reputation AS UserReputation,
    uas.UserCreationDate,
    uas.TotalPostsCreated,
    uas.GoldBadgesCount,
    ped.Title AS PostTitle,
    ped.PostCreationDate,
    ped.PostScore,
    ped.ViewCount,
    ped.UpvoteCount,
    ped.DownvoteCount,
    ped.DistinctFavoritingUsers,
    ped.EditRevisionCount,
    ped.InitialCloseReason,
    tpm.TagName AS PrimaryTagName,
    tpm.GlobalTagUsageCount,
    pla.TotalLinkedPosts,
    pla.DuplicateLinksCount,
    COALESCE(EXTRACT(EPOCH FROM (ped.LastActivityDate - ped.PostCreationDate)) / 86400.0, 0.0) AS DaysSinceCreationToLastActivity, -- Time in days
    (ped.UpvoteCount + ped.DistinctFavoritingUsers) / NULLIF(ped.DownvoteCount + 1.0, 0.0) AS UpvoteToDownvoteRatio,
    CASE
        WHEN ped.ViewCount > 5000 AND ped.PostScore > 100 AND ped.EditRevisionCount >= 5 THEN 'Viral & Highly Curated'
        WHEN ped.ViewCount > 1000 AND ped.PostScore > 50 THEN 'High Impact'
        WHEN ped.ViewCount > 500 AND ped.PostScore > 20 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS PostEngagementCategory,
    ped.LatestCommenterDisplayName,
    ped.LatestCommenterReputation,
    (SELECT AVG(ph_time.CreationDate - ph_time_prev.CreationDate)
     FROM PostHistory ph_time
     JOIN PostHistory ph_time_prev ON ph_time.PostId = ph_time_prev.PostId
                                   AND ph_time.PostHistoryTypeId IN (4, 5, 6)
                                   AND ph_time_prev.PostHistoryTypeId IN (4, 5, 6)
                                   AND ph_time.CreationDate > ph_time_prev.CreationDate
     WHERE ph_time.PostId = ped.PostId
     GROUP BY ph_time.PostId) AS AvgEditInterval, -- Average time between edits
    RANK() OVER (PARTITION BY uas.UserId ORDER BY ped.PostScore DESC, ped.ViewCount DESC) AS UserPostRankByScoreViews,
    LAG(ped.PostScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY ped.PostCreationDate) AS PreviousPostScoreByCreationDate,
    SUM(ped.UpvoteCount) OVER (PARTITION BY tpm.TagName ORDER BY uas.Reputation DESC) AS TotalUpvotesForTagByReputableUsers,
    NTH_VALUE(ped.Title, 1) OVER (PARTITION BY uas.UserId ORDER BY ped.Score DESC, ped.CreationDate DESC) AS TopScoredPostTitleByUser,
    PERCENT_RANK() OVER (ORDER BY ped.ViewCount DESC, ped.PostScore DESC) AS GlobalPostPopularityPercentile
FROM UserActivityStats uas
JOIN PostEngagementDetails ped ON uas.UserId = ped.OwnerUserId
LEFT JOIN TagPerformanceMetrics tpm ON ped.PostId = tpm.PostId AND tpm.TagOrderForPost = 1 -- Get the primary tag
LEFT JOIN PostLinkAnalysis pla ON ped.PostId = pla.PostId
WHERE
    uas.TotalQuestionsAsked > 5 AND ped.PostTypeId = 1 -- Only questions from users who asked at least 5 questions
    AND uas.Reputation > 2000
    AND ped.ViewCount > 100
    AND (ped.PostScore > 10 OR ped.FavoriteCount > 2)
    AND (
        ped.Title ILIKE '%sql%'
        OR
        ped.Body ILIKE '%performance%'
        OR
        tpm.TagName ILIKE '%database%'
    )
    AND uas.DisplayName IS NOT NULL
    AND ped.ClosedDate IS NULL
    AND AGE(NOW(), uas.UserCreationDate) > INTERVAL '1 year' -- User created more than a year ago
    AND (ped.EditRevisionCount >= 2 OR ped.CommentCount >= 5) -- Posts with significant activity
ORDER BY
    GlobalPostPopularityPercentile DESC,
    UserReputation DESC,
    DaysSinceCreationToLastActivity DESC
LIMIT 500;