-- {"query": "1066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2945} 

WITH UserEngagementSummary AS (
    -- Summarizes core user activity and reputation metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        u.Location,
        u.AboutMe,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT CASE WHEN vp.VoteTypeId = 2 THEN vp.Id END) AS TotalUpVotesReceivedOnPosts,
        COUNT(DISTINCT CASE WHEN vp.VoteTypeId = 3 THEN vp.Id END) AS TotalDownVotesReceivedOnPosts,
        COUNT(DISTINCT CASE WHEN vc.VoteTypeId = 2 THEN vc.Id END) AS TotalUpVotesReceivedOnComments,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        (EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60 * 60 * 24))::int AS AccountAgeDays, -- Account age in days
        COALESCE(u.Location, 'Unknown Region') AS UserLocationNormalized
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes vp ON p.Id = vp.PostId -- Votes on user's posts
    LEFT JOIN Votes vc ON c.Id = vc.PostId AND vc.VoteTypeId = 2 -- Upvotes on user's comments (assuming comment votes can be joined similarly to post votes, or adjusting if separate table)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2016-01-01' -- Focus on users active after a certain date
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe
),
PostContentAnalysis AS (
    -- Analyzes content metrics and history events for posts
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS ParsedTags, -- Parse tags into an array
        (
            SELECT AVG(c.Score)
            FROM Comments c
            WHERE c.PostId = p.Id
        ) AS AverageCommentScoreOnPost, -- Scalar subquery for average comment score
        COUNT(ph.Id) AS TotalHistoryEvents,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS WasClosedOrDeleted, -- Aggregated moderation status
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditHistoryDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate >= '2016-01-01' -- Matching user filter
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
             p.CommentCount, p.FavoriteCount, p.CreationDate, p.LastActivityDate, p.ClosedDate, p.Body, p.Title, p.Tags
),
RankedUserAnswerQuality AS (
    -- Ranks user's answers and computes acceptance rates
    SELECT
        pca.OwnerUserId AS UserId,
        pca.PostId AS AnswerPostId,
        pca.PostScore AS AnswerScore,
        pca.PostCreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY pca.OwnerUserId ORDER BY pca.PostScore DESC, pca.PostCreationDate DESC) AS AnswerScoreRank,
        LAG(pca.PostCreationDate, 1, pca.PostCreationDate) OVER (PARTITION BY pca.OwnerUserId ORDER BY pca.PostCreationDate) AS PreviousAnswerCreationDate, -- LAG for time difference
        (SELECT p_parent.AcceptedAnswerId = pca.PostId FROM Posts p_parent WHERE p_parent.Id = pca.ParentId AND p_parent.PostTypeId = 1) AS IsAcceptedAnswer -- Correlated subquery for acceptance
    FROM PostContentAnalysis pca
    WHERE pca.PostTypeId = 2 -- Only answers
),
UserTagDominance AS (
    -- Identifies the most dominant tag for each user based on post score
    SELECT
        pca.OwnerUserId AS UserId,
        t.TagName,
        SUM(pca.PostScore) AS TagContributionScore,
        COUNT(pca.PostId) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY pca.OwnerUserId ORDER BY SUM(pca.PostScore) DESC, COUNT(pca.PostId) DESC) AS TagRank
    FROM PostContentAnalysis pca
    CROSS JOIN UNNEST(pca.ParsedTags) AS t(TagName) -- Expands tags array into rows
    WHERE pca.PostTypeId IN (1, 2) AND pca.ParsedTags IS NOT NULL
    GROUP BY pca.OwnerUserId, t.TagName
),
FinalUserMetrics AS (
    -- Combines all previous CTEs and computes final weighted scores and tiers
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.UserLocationNormalized,
        ues.AccountAgeDays,
        ues.TotalQuestionsAsked,
        ues.TotalAnswersPosted,
        ues.TotalCommentsMade,
        ues.TotalUpVotesReceivedOnPosts,
        ues.GoldBadgesCount,
        ues.SilverBadgesCount,
        ues.BronzeBadgesCount,
        ues.AboutMe,
        -- Weighted base contribution score
        (ues.Reputation * 0.01 +
         ues.TotalPostsCreated * 0.5 +
         ues.TotalCommentsMade * 0.2 +
         ues.TotalUpVotesReceivedOnPosts * 0.3 +
         ues.GoldBadgesCount * 10 +
         ues.SilverBadgesCount * 5 +
         ues.BronzeBadgesCount * 1) AS BaseContributionScore,
        AVG(ruaq.AnswerScore) FILTER (WHERE ruaq.AnswerScoreRank <= 5) OVER (PARTITION BY ues.UserId) AS AvgTop5AnswerScore, -- Conditional aggregation with window function
        COUNT(pca.PostId) FILTER (WHERE pca.WasClosedOrDeleted = 1) AS PostsClosedOrDeletedCount,
        SUM(CASE WHEN ruaq.IsAcceptedAnswer THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        (SUM(CASE WHEN ruaq.IsAcceptedAnswer THEN 1 ELSE 0 END) * 1.0 / NULLIF(ues.TotalAnswersPosted, 0)) AS AnswerAcceptanceRate,
        MAX(pca.LastActivityDate) OVER (PARTITION BY ues.UserId) AS MostRecentPostActivity, -- Latest activity from any post
        tud.TagName AS TopContributingTagName,
        tud.TagContributionScore AS TopTagScore,
        NTILE(5) OVER (ORDER BY ues.Reputation DESC, ues.TotalPostsCreated DESC) AS UserReputationTier -- NTILE for relative ranking
    FROM UserEngagementSummary ues
    LEFT JOIN PostContentAnalysis pca ON ues.UserId = pca.OwnerUserId
    LEFT JOIN RankedUserAnswerQuality ruaq ON ues.UserId = ruaq.UserId
    LEFT JOIN UserTagDominance tud ON ues.UserId = tud.UserId AND tud.TagRank = 1 -- Only join for the top tag
    GROUP BY ues.UserId, ues.DisplayName, ues.Reputation, ues.UserLocationNormalized, ues.AccountAgeDays,
             ues.TotalQuestionsAsked, ues.TotalAnswersPosted, ues.TotalCommentsMade, ues.TotalUpVotesReceivedOnPosts,
             ues.GoldBadgesCount, ues.SilverBadgesCount, ues.BronzeBadgesCount, ues.AboutMe,
             tud.TagName, tud.TagContributionScore
)
SELECT
    fum.UserId,
    fum.DisplayName,
    fum.Reputation,
    fum.UserLocationNormalized,
    fum.AccountAgeDays,
    fum.TotalQuestionsAsked,
    fum.TotalAnswersPosted,
    fum.TotalCommentsMade,
    fum.BaseContributionScore,
    fum.AvgTop5AnswerScore,
    fum.PostsClosedOrDeletedCount,
    fum.AcceptedAnswersCount,
    fum.AnswerAcceptanceRate,
    fum.TopContributingTagName,
    fum.TopTagScore,
    fum.UserReputationTier,
    -- Complex calculated score factoring in various metrics
    (fum.BaseContributionScore * 0.6 +
     COALESCE(fum.AvgTop5AnswerScore, 0) * 0.15 +
     COALESCE(fum.AnswerAcceptanceRate, 0) * 100 * 0.1 + -- 10% weight to acceptance rate
     COALESCE(fum.TopTagScore, 0) * 0.005 +
     fum.PostsClosedOrDeletedCount * -0.01 -- Penalty for closed/deleted posts
    ) AS FinalAggregatePerformanceScore,
    -- Categorization using CASE expressions and NULL logic
    CASE
        WHEN fum.Reputation >= 10000 AND fum.GoldBadgesCount >= 5 AND fum.TotalAnswersPosted >= 200 THEN 'Legendary Guru'
        WHEN fum.Reputation >= 5000 AND fum.TotalAnswersPosted >= 100 AND fum.AnswerAcceptanceRate > 0.7 THEN 'Master Contributor'
        WHEN fum.Reputation >= 1000 AND fum.TotalQuestionsAsked >= 30 AND fum.TotalAnswersPosted >= 50 THEN 'Active Community Member'
        WHEN fum.AccountAgeDays >= 730 AND fum.TotalPostsCreated >= 20 THEN 'Seasoned Participant'
        ELSE 'Emerging User'
    END AS UserRoleCategory,
    -- String expression for a unique user identifier
    UPPER(LEFT(COALESCE(fum.DisplayName, 'ANONYMOUS'), 4)) || '-' ||
    SUBSTRING(MD5(fum.UserLocationNormalized), 1, 6) || '-' ||
    LPAD(fum.UserId::text, 5, '0') AS UserIdentifierCode,
    -- Subquery to check if user has linked or duplicated any posts as a related post
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = fum.UserId)
          AND pl.LinkTypeId IN (1, 3) -- Linked or Duplicate
          AND pl.CreationDate > (fum.MostRecentPostActivity - INTERVAL '1 year')
    ) AS HasRecentInterlinkedPosts
FROM FinalUserMetrics fum
WHERE
    fum.Reputation >= 200 -- Minimum reputation
    AND fum.TotalPostsCreated > 5
    AND (fum.AboutMe LIKE '%developer%' OR fum.AboutMe LIKE '%programmer%' OR fum.AboutMe IS NULL) -- Complex predicate with NULL check
    AND fum.AccountAgeDays >= 90
    AND NOT EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = fum.UserId AND b.Name = 'Critic' AND b.Date > (NOW() - INTERVAL '6 months') -- Exclude recent "critics"
    )
ORDER BY FinalAggregatePerformanceScore DESC, fum.Reputation DESC, fum.MostRecentPostActivity DESC
LIMIT 1000;
