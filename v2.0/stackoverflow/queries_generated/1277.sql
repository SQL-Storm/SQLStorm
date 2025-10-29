-- {"query": "1277.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3572} 

WITH UserEngagementSummary AS (
    -- Aggregates core user activity metrics from Posts and Comments, including calculation of account age and net votes.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsContributed,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(p.ViewCount), 0) AS AggregatePostViews,
        COALESCE(SUM(p.Score), 0) AS AggregatePostScore,
        COALESCE(SUM(p.FavoriteCount), 0) AS AggregatePostFavorites,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS AggregateCommentScore,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS AccountAgeDays,
        (u.UpVotes - u.DownVotes) AS NetVotesGivenReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
UserBadgeAchievements AS (
    -- Summarizes badge counts by class and type for each user, providing a latest badge date.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MAX(b.Date) AS LatestBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
PostVersionHistoryAnalysis AS (
    -- Analyzes post history to count specific events like closures, reopenings, edits, and average days between edits.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostClosureCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostReopenCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS PostEditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        -- Window function: Calculate average days between successive edits for a post.
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))))
        FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6) AND LAG(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) IN (4,5,6)) / 86400.0 AS AvgDaysBetweenConsecutiveEdits
    FROM PostHistory ph
    GROUP BY ph.PostId
),
DetailedPostAttributes AS (
    -- Gathers detailed attributes for posts, including word count, formatted tags, linked post counts, and distinct commenter counts.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Title,
        p.Body,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        pva.TotalHistoryEvents,
        pva.PostClosureCount,
        pva.PostReopenCount,
        pva.PostEditCount,
        pva.AvgDaysBetweenConsecutiveEdits,
        COALESCE(SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END), 0) AS LinkedPostReferences,
        COALESCE(SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END), 0) AS DuplicatePostReferences,
        (SELECT COUNT(DISTINCT c_sub.UserId) FROM Comments c_sub WHERE c_sub.PostId = p.Id AND c_sub.UserId IS NOT NULL) AS DistinctCommenters,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, ' ', '')) + 1 AS BodyWordCount,
        NULLIF(TRIM(REPLACE(REPLACE(p.Tags, '><', ', '), '<', ''), '>'), '') AS FormattedTags,
        -- Window function: Calculate the average bounty amount for posts by a specific user.
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) OVER (PARTITION BY p.OwnerUserId) AS AverageBountyOnOwnerPosts,
        MAX(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId) AS OwnerLatestActivityAcrossPosts
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN PostVersionHistoryAnalysis pva ON p.Id = pva.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8 -- BountyStart VoteType
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Body, p.Tags, p.AnswerCount, p.CommentCount,
        pva.TotalHistoryEvents, pva.PostClosureCount, pva.PostReopenCount, pva.PostEditCount, pva.AvgDaysBetweenConsecutiveEdits
    HAVING COUNT(pl.Id) > 0 OR p.CommentCount > 0 OR p.Score > 0 -- Filter for posts with some interaction
),
RecentHighImpactPosts AS (
    -- Combines recent popular questions and answers using UNION ALL, then ranks them based on score and views/comments.
    SELECT
        'Question' AS PostCategory,
        dpa.PostId,
        dpa.Title,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.PostScore,
        dpa.ViewCount,
        dpa.CommentCount,
        dpa.AnswerCount,
        dpa.LinkedPostReferences,
        -- Window function: Rank questions by score and view count.
        RANK() OVER (ORDER BY dpa.PostScore DESC, dpa.ViewCount DESC, dpa.PostCreationDate DESC) AS PostEngagementRank
    FROM DetailedPostAttributes dpa
    WHERE dpa.PostTypeId = 1 AND dpa.PostCreationDate >= NOW() - INTERVAL '1 year' AND dpa.PostScore > 5
    UNION ALL
    SELECT
        'Answer' AS PostCategory,
        dpa.PostId,
        dpa.Title,
        dpa.OwnerUserId,
        dpa.PostCreationDate,
        dpa.PostScore,
        dpa.ViewCount,
        dpa.CommentCount,
        NULL AS AnswerCount, -- Answers don't have direct answer_count
        dpa.LinkedPostReferences,
        -- Window function: Rank answers by score and comment count.
        RANK() OVER (ORDER BY dpa.PostScore DESC, dpa.CommentCount DESC, dpa.PostCreationDate DESC) AS PostEngagementRank
    FROM DetailedPostAttributes dpa
    WHERE dpa.PostTypeId = 2 AND dpa.PostCreationDate >= NOW() - INTERVAL '6 months' AND dpa.PostScore > 3
)
-- Final comprehensive query joining all CTEs to generate a detailed user profile report.
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.AccountAgeDays,
    ues.TotalPostsContributed,
    ues.QuestionsAsked,
    ues.AnswersProvided,
    ues.AggregatePostViews,
    ues.AggregatePostScore,
    ues.TotalCommentsMade,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uba.TagBasedBadges, 0) AS TagBasedBadges,
    COALESCE(uba.LatestBadgeAwardDate, ues.UserCreationDate) AS EffectiveLatestUserActivityDate,
    -- Complex calculated score for overall user influence, combining multiple metrics with specific weights.
    (ues.Reputation * 0.15 + ues.AggregatePostScore * 0.4 + ues.AggregatePostViews * 0.005 + ues.TotalCommentsMade * 0.1 + COALESCE(uba.GoldBadges, 0) * 8 + COALESCE(uba.TagBasedBadges, 0) * 2 + ues.NetVotesGivenReceived * 0.01) AS OverallUserInfluenceScore,
    -- Average distinct commenters per post owned by the user.
    AVG(dpa.DistinctCommenters) FILTER (WHERE dpa.OwnerUserId = ues.UserId) AS AvgDistinctCommentersPerOwnedPost,
    -- Percentage of user's posts that have been edited more than twice, indicating active maintenance.
    (SUM(CASE WHEN dpa.PostEditCount > 2 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(dpa.PostId), 0)) AS PctPostsMultiEdited,
    -- Correlated subquery: Checks if the user holds a 'Gold' badge for a tag that is present in at least one of their owned posts.
    EXISTS (
        SELECT 1
        FROM Badges b_corr
        JOIN Tags t_corr ON LOWER(b_corr.Name) = LOWER(t_corr.TagName) -- Assuming badge name can directly map to tag name
        WHERE b_corr.UserId = ues.UserId
          AND b_corr.Class = 1 -- Gold badge
          AND EXISTS (
              SELECT 1
              FROM DetailedPostAttributes dpa_corr
              WHERE dpa_corr.OwnerUserId = ues.UserId
                AND dpa_corr.FormattedTags LIKE '%' || t_corr.TagName || '%'
                AND dpa_corr.PostCreationDate >= NOW() - INTERVAL '3 years' -- Only consider recent tags
          )
    ) AS HasGoldBadgeForOwnActiveTag,
    -- Window function: Ranks users within their "reputation tier" based on their calculated influence score.
    RANK() OVER (PARTITION BY (
        CASE
            WHEN ues.Reputation >= 50000 THEN 'Elite'
            WHEN ues.Reputation >= 10000 THEN 'HighTier'
            WHEN ues.Reputation >= 1000 THEN 'MidTier'
            ELSE 'LowTier'
        END
    ) ORDER BY (ues.Reputation * 0.15 + ues.AggregatePostScore * 0.4 + ues.AggregatePostViews * 0.005 + ues.TotalCommentsMade * 0.1 + COALESCE(uba.GoldBadges, 0) * 8 + COALESCE(uba.TagBasedBadges, 0) * 2 + ues.NetVotesGivenReceived * 0.01) DESC) AS ReputationTierInfluenceRank,
    -- Categorizes user's primary contribution role based on post type counts, using NULL logic for clarity.
    CASE
        WHEN ues.QuestionsAsked > ues.AnswersProvided AND ues.QuestionsAsked > 0 THEN 'Primary Questioner'
        WHEN ues.AnswersProvided > ues.QuestionsAsked AND ues.AnswersProvided > 0 THEN 'Primary Answerer'
        WHEN ues.TotalPostsContributed > 0 THEN 'Balanced Contributor'
        WHEN ues.TotalCommentsMade > 0 THEN 'Commentator Only'
        ELSE 'Passive User'
    END AS UserPrimaryContributionRole,
    -- String manipulation: Extracts and capitalizes the first 7 characters of the user's display name.
    UPPER(SUBSTRING(ues.DisplayName, 1, 7)) AS DisplayNamePrefix,
    -- String manipulation: Checks if the user's AboutMe contains specific keywords.
    (CASE WHEN Users.AboutMe LIKE '%SQL%' OR Users.AboutMe LIKE '%database%' OR Users.AboutMe LIKE '%developer%' THEN TRUE ELSE FALSE END) AS IsTechnicalBio,
    -- Aggregated information from RecentHighImpactPosts
    MAX(CASE WHEN rhip.PostCategory = 'Question' AND rhip.PostEngagementRank <= 10 THEN rhip.Title ELSE NULL END) AS Top10RecentQuestionTitle,
    MAX(CASE WHEN rhip.PostCategory = 'Answer' AND rhip.PostEngagementRank <= 10 THEN rhip.Title ELSE NULL END) AS Top10RecentAnswerTitle,
    SUM(CASE WHEN rhip.PostCategory = 'Question' THEN 1 ELSE 0 END) AS TotalRecentHighImpactQuestions,
    SUM(CASE WHEN rhip.PostCategory = 'Answer' THEN 1 ELSE 0 END) AS TotalRecentHighImpactAnswers
FROM UserEngagementSummary ues
LEFT JOIN UserBadgeAchievements uba ON ues.UserId = uba.UserId
LEFT JOIN DetailedPostAttributes dpa ON ues.UserId = dpa.OwnerUserId
LEFT JOIN RecentHighImpactPosts rhip ON ues.UserId = rhip.OwnerUserId
LEFT JOIN Users ON ues.UserId = Users.Id -- To access Users.AboutMe
WHERE
    ues.Reputation > 500 AND ues.AccountAgeDays > 90 -- Filter for more established and active users
    AND (ues.DisplayName IS NOT NULL AND ues.DisplayName <> '' AND ues.DisplayName NOT LIKE 'user%') -- Exclude generic/deleted users
    AND ues.LastAccessDate >= NOW() - INTERVAL '1 year' -- Actively participating users
GROUP BY
    ues.UserId, ues.DisplayName, ues.Reputation, ues.AccountAgeDays, ues.TotalPostsContributed, ues.QuestionsAsked,
    ues.AnswersProvided, ues.AggregatePostViews, ues.AggregatePostScore, ues.TotalCommentsMade,
    uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, uba.TagBasedBadges, uba.LatestBadgeAwardDate,
    ues.UserCreationDate, ues.NetVotesGivenReceived, Users.AboutMe
ORDER BY OverallUserInfluenceScore DESC, ues.Reputation DESC
LIMIT 5000;
