-- {"query": "1967.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2882} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(GREATEST(COALESCE(p.LastActivityDate, '1900-01-01'), COALESCE(c.CreationDate, '1900-01-01'), COALESCE(b.Date, '1900-01-01'))) AS LastContributionDate,
        EXTRACT(DAY FROM (NOW() - u.CreationDate)) AS DaysSinceCreation,
        u.Views AS ProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Location AS UserLocation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.CommunityOwnedDate,
        pt.Name AS PostTypeName,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24) AND ph.CreationDate > NOW() - INTERVAL '90 days') AS RecentEditCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS CloseVoteHistoryCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopPostRank
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.ParentId, p.ClosedDate, p.CommunityOwnedDate, pt.Name
),
RecentSignificantPostActivity AS (
    SELECT
        pem.PostId,
        pem.OwnerUserId,
        pem.PostTypeName,
        pem.PostScore,
        pem.ViewCount,
        pem.AnswerCount,
        pem.CommentCount,
        pem.FavoriteCount,
        pem.RecentEditCount,
        CASE
            WHEN pem.PostTypeId = 1 THEN 'Question'
            WHEN pem.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        NULLIF(COALESCE(pem.ClosedDate::VARCHAR, 'Open'), 'Open') AS ClosedStatus,
        SUM(pem.UpvotesReceived) OVER (PARTITION BY pem.OwnerUserId) AS UserTotalUpvotesOnPosts,
        SUM(pem.DownvotesReceived) OVER (PARTITION BY pem.OwnerUserId) AS UserTotalDownvotesOnPosts,
        AVG(pem.PostScore) OVER (PARTITION BY pem.OwnerUserId) AS AvgPostScorePerUser,
        RANK() OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostScore DESC) AS PostScoreRankByUser
    FROM PostEngagementMetrics pem
    WHERE pem.PostCreationDate > NOW() - INTERVAL '1 year'
    AND (pem.PostScore > 50 OR pem.CommentCount > 10 OR pem.FavoriteCount > 5)
),
UserTagDominance AS (
    SELECT
        u.Id AS UserId,
        tag_name.name AS Tag,
        COUNT(DISTINCT p.Id) AS PostsPerTag,
        SUM(COALESCE(p.Score, 0)) AS ScorePerTag,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC, SUM(COALESCE(p.Score, 0)) DESC) AS TagRankByUser
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT DISTINCT
            p_inner.Id AS PostId,
            TRIM(UNNEST(string_to_array(SUBSTRING(p_inner.Tags, 2, LENGTH(p_inner.Tags) - 2), '><'))) AS name
        FROM Posts p_inner
        WHERE p_inner.Tags IS NOT NULL AND LENGTH(p_inner.Tags) > 2
    ) AS tag_name ON p.Id = tag_name.PostId
    GROUP BY u.Id, tag_name.name
),
UserPostLinkingBehavior AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl.Id) AS TotalLinksCreated,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS DirectLinksCount,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinksCount,
        COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelatedPostsLinked,
        NULLIF(SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END)::NUMERIC / COUNT(pl.Id), 0) AS DuplicateLinkRatio
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopTagsPerUser AS (
    SELECT
        UserId,
        Tag,
        PostsPerTag,
        ScorePerTag,
        TagRankByUser
    FROM UserTagDominance
    WHERE TagRankByUser <= 3
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.TotalComments,
    uas.TotalCommentScore,
    uas.TotalBadges,
    uas.LastContributionDate,
    uas.DaysSinceCreation,
    uas.ProfileViews,
    uas.UserUpVotes,
    uas.UserDownVotes,
    (uas.UserUpVotes - uas.UserDownVotes) AS NetUserVotes,
    uas.UserLocation,
    AVG(rspa.PostScore) AS AvgRecentPostScore,
    MAX(rspa.PostScore) AS MaxRecentPostScore,
    COUNT(DISTINCT rspa.PostId) AS TotalRecentSignificantPosts,
    MAX(CASE WHEN rspa.PostScoreRankByUser = 1 THEN rspa.PostTypeName END) AS TopPostType,
    MAX(CASE WHEN rspa.PostScoreRankByUser = 1 THEN rspa.PostScore END) AS TopPostScore,
    MAX(rspa.ClosedStatus) AS LastClosedStatusOfSignificantPost,
    COALESCE(uplb.TotalLinksCreated, 0) AS TotalLinksCreatedByUser,
    COALESCE(uplb.DuplicateLinkRatio, 0.0) AS DuplicateLinkRatioByUser,
    STRING_AGG(DISTINCT ttpu.Tag || ' (' || ttpu.PostsPerTag || ')', '; ') FILTER (WHERE ttpu.Tag IS NOT NULL) AS TopUserTagsWithCounts,
    SUM(CASE WHEN ttpu.Tag ILIKE '%sql%' OR ttpu.Tag ILIKE '%database%' THEN ttpu.PostsPerTag ELSE 0 END) AS SQL_RelatedPostsCount,
    (SELECT COUNT(DISTINCT ph_inner.PostId)
     FROM PostHistory ph_inner
     WHERE ph_inner.UserId = uas.UserId
       AND ph_inner.PostHistoryTypeId IN (5, 8)
       AND ph_inner.CreationDate > NOW() - INTERVAL '30 days'
       AND EXISTS (
           SELECT 1 FROM Posts p_inner
           WHERE p_inner.Id = ph_inner.PostId
             AND p_inner.OwnerUserId = uas.UserId
             AND p_inner.LastActivityDate > NOW() - INTERVAL '60 days'
             AND p_inner.ClosedDate IS NULL
       )
    ) AS RecentOwnActivePostEdits,
    (SELECT COUNT(DISTINCT b.Id)
     FROM Badges b
     WHERE b.UserId = uas.UserId
       AND b.Class = 1
       AND b.TagBased = TRUE
    ) AS GoldTagBadgesCount,
    CASE
        WHEN uas.Reputation > 50000 AND uas.TotalQuestions > 100 AND uas.TotalAnswers > 250 AND uas.TotalPostScore > 10000 THEN 'Legendary Contributor'
        WHEN uas.Reputation > 10000 AND uas.TotalQuestions > 50 AND uas.TotalAnswers > 150 AND uas.TotalPostScore > 5000 THEN 'Expert Advisor'
        WHEN uas.Reputation > 2500 AND uas.TotalQuestions > 15 AND uas.TotalAnswers > 50 AND uas.TotalPostScore > 1000 THEN 'Active Contributor'
        ELSE 'Engaged User'
    END AS UserContributionTier,
    COALESCE(NULLIF(TRIM(SUBSTRING(uas.UserLocation FROM POSITION(',' IN uas.UserLocation) + 1)), ''), uas.UserLocation) AS NormalizedLocationFragment -- String expression and NULL logic
FROM UserActivitySummary uas
LEFT JOIN RecentSignificantPostActivity rspa ON uas.UserId = rspa.OwnerUserId
LEFT JOIN UserPostLinkingBehavior uplb ON uas.UserId = uplb.UserId
LEFT JOIN TopTagsPerUser ttpu ON uas.UserId = ttpu.UserId
WHERE uas.Reputation > 500
AND uas.TotalPosts > 10
AND uas.LastAccessDate > NOW() - INTERVAL '6 months'
GROUP BY
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.TotalComments,
    uas.TotalCommentScore,
    uas.TotalBadges,
    uas.LastContributionDate,
    uas.DaysSinceCreation,
    uas.ProfileViews,
    uas.UserUpVotes,
    uas.UserDownVotes,
    uas.UserLocation,
    uplb.TotalLinksCreated,
    uplb.DuplicateLinkRatio
HAVING
    COUNT(DISTINCT rspa.PostId) > 0
    AND (
        (uas.TotalQuestions > 0 AND AVG(rspa.PostScore) > 25)
        OR (uas.TotalAnswers > 0 AND AVG(rspa.PostScore) > 10)
    )
ORDER BY
    uas.Reputation DESC,
    TotalRecentSignificantPosts DESC,
    SQL_RelatedPostsCount DESC NULLS LAST;
