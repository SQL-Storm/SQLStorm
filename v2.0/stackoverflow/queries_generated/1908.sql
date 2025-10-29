-- {"query": "1908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3317} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates user-level engagement, badge information, and calculates derived user attributes.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COALESCE(u.Location, 'Global') AS UserLocationCategory, -- NULL handling
        CASE
            WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 200 THEN 'Very Detailed Bio'
            WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) BETWEEN 50 AND 200 THEN 'Moderate Bio'
            WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) < 50 THEN 'Minimal Bio'
            ELSE 'No Bio Provided'
        END AS AboutMeDescriptor,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        SUM(COALESCE(p.Score, 0)) AS SumOfPostScores,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(p.CreationDate) AS LatestPostActivityDate,
        MIN(p.CreationDate) AS EarliestPostActivityDate,
        COUNT(DISTINCT b.Name) AS UniqueBadgeNames,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe
),
PostContentAnalysis AS (
    -- CTE 2: Analyzes post content, tags, and history events for individual posts.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount AS QuestionAnswerCount, -- Only relevant for PostTypeId = 1
        p.FavoriteCount,
        p.ClosedDate,
        LENGTH(REPLACE(REPLACE(REPLACE(COALESCE(p.Tags, '||'), '<', ''), '>', ','), '||', '')) AS TagsConcatenatedLength,
        CARDINALITY(string_to_array(SUBSTRING(COALESCE(p.Tags, '<>'), 2, LENGTH(COALESCE(p.Tags, '<>'))-2), '><')) AS DistinctTagCount, -- Assumes PostgreSQL string_to_array
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteVoteCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('101', '1') THEN 'Duplicate' -- Modern/old duplicate close reason
                 WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('102', '2') THEN 'Off-topic'
                 WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('103', '4') THEN 'Needs Clarity' -- Modern needs details / old not a real question
                 ELSE NULL END) AS LastMajorCloseReason,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicateLinks,
        -- Correlated subquery: Check if a post has been edited by a user different from its owner
        EXISTS (
            SELECT 1
            FROM PostHistory ph_edit_user
            WHERE ph_edit_user.PostId = p.Id
              AND ph_edit_user.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
              AND ph_edit_user.UserId IS NOT NULL
              AND ph_edit_user.UserId != p.OwnerUserId
        ) AS HasExternalEditor,
        -- String expression and NULL logic in Body analysis
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', ''))) / LENGTH('<code>') AS CodeBlockCount,
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastActivityDate
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.ClosedDate, p.Tags, p.Body, p.LastEditDate
),
UserPostPerformance AS (
    -- CTE 3: Combines user and post data, applies window functions for ranking and sequential analysis.
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        pca.PostId,
        pca.PostTypeId,
        pca.PostScore,
        pca.ViewCount,
        pca.QuestionAnswerCount,
        pca.FavoriteCount,
        pca.ContentEditCount,
        pca.CloseVoteCount,
        pca.LastMajorCloseReason,
        pca.DistinctTagCount,
        pca.HasExternalEditor,
        pca.CodeBlockCount,
        pca.EffectiveLastActivityDate,
        ues.UserCreationDate,
        ues.TotalPostsCreated,
        ues.GoldBadgesCount,
        -- Window function: Rank posts by score within each user
        RANK() OVER (PARTITION BY ues.UserId ORDER BY pca.PostScore DESC, pca.PostCreationDate ASC) AS PostScoreRankPerUser,
        -- Window function: Calculate average score of previous 3 posts by the user
        AVG(pca.PostScore) OVER (PARTITION BY ues.UserId ORDER BY pca.PostCreationDate ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS AvgPrev3PostScore,
        -- Window function: Time difference in days to the next post by the same user
        EXTRACT(EPOCH FROM (LEAD(pca.PostCreationDate, 1) OVER (PARTITION BY ues.UserId ORDER BY pca.PostCreationDate) - pca.PostCreationDate)) / (60 * 60 * 24) AS DaysToNextPost,
        -- Complex calculation incorporating NULL logic for acceptance rate
        NULLIF(SUM(CASE WHEN p_ans.AcceptedAnswerId = pca.PostId THEN 1 ELSE 0 END) OVER (PARTITION BY ues.UserId, pca.PostTypeId), 0) /
        NULLIF(COUNT(CASE WHEN pca.PostTypeId = 2 AND p_ans.ParentId = pca.PostId THEN 1 ELSE NULL END) OVER (PARTITION BY ues.UserId, pca.PostTypeId), 0) AS UserAnswerAcceptanceRatio
    FROM
        UserEngagementSummary ues
    INNER JOIN
        PostContentAnalysis pca ON ues.UserId = pca.OwnerUserId
    LEFT JOIN
        Posts p_ans ON pca.PostId = p_ans.AcceptedAnswerId OR (pca.PostTypeId = 2 AND pca.PostId = p_ans.ParentId)
    WHERE
        ues.Reputation >= 500
        AND pca.PostScore > 0
        AND pca.PostCreationDate BETWEEN '2021-01-01' AND '2023-12-31' -- Filter for recent activity
        AND NOT EXISTS ( -- Correlated subquery: Exclude posts that were migrated away
            SELECT 1
            FROM PostHistory ph_migrated
            WHERE ph_migrated.PostId = pca.PostId
              AND ph_migrated.PostHistoryTypeId = 35 -- Post Migrated Away
        )
    GROUP BY
        ues.UserId, ues.DisplayName, ues.Reputation, pca.PostId, pca.PostTypeId, pca.PostScore, pca.ViewCount, pca.QuestionAnswerCount, pca.FavoriteCount, pca.ContentEditCount, pca.CloseVoteCount, pca.LastMajorCloseReason, pca.DistinctTagCount, pca.HasExternalEditor, pca.CodeBlockCount, pca.EffectiveLastActivityDate, ues.UserCreationDate, ues.TotalPostsCreated, ues.GoldBadgesCount, pca.PostCreationDate, p_ans.AcceptedAnswerId, p_ans.ParentId
),
UserBehaviorSegmentation AS (
    -- CTE 4: Segments users based on their post performance and engagement, aggregates at user level.
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GoldBadgesCount,
        TotalPostsCreated,
        SUM(PostScore) AS AggregatePostScore,
        AVG(PostScore) AS AveragePostScore,
        MAX(PostScoreRankPerUser) AS HighestPostRank, -- Lower rank number is better
        AVG(AvgPrev3PostScore) AS OverallAvgPrevPostScore,
        AVG(DaysToNextPost) AS AvgDaysBetweenPosts,
        SUM(ContentEditCount) AS TotalContentEdits,
        SUM(CloseVoteCount) AS TotalClosedPostsInitiated,
        SUM(CASE WHEN LastMajorCloseReason = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateClosedPosts,
        SUM(CASE WHEN HasExternalEditor THEN 1 ELSE 0 END) AS PostsWithExternalEdits,
        SUM(CodeBlockCount) AS TotalCodeBlocksInPosts,
        AVG(UserAnswerAcceptanceRatio) AS OverallUserAnswerAcceptanceRatio,
        -- Complex user categorization using CASE statements and logical operators
        CASE
            WHEN GoldBadgesCount >= 3 AND Reputation >= 10000 AND TotalPostsCreated >= 50 THEN 'High-Achiever Elite'
            WHEN GoldBadgesCount >= 1 AND Reputation >= 5000 AND TotalPostsCreated >= 20 THEN 'Established Contributor'
            WHEN Reputation BETWEEN 1000 AND 4999 AND TotalPostsCreated >= 10 THEN 'Active Contributor'
            ELSE 'Emerging Participant'
        END AS UserCategory,
        -- Calculate a composite user engagement score
        (Reputation * 0.4) +
        (AggregatePostScore * 0.1) +
        (GoldBadgesCount * 5) +
        (TotalPostsCreated * 0.5) -
        (TotalClosedPostsInitiated * 2) +
        (COALESCE(AVG(UserAnswerAcceptanceRatio), 0) * 100) AS CompositeEngagementScore
    FROM
        UserPostPerformance
    GROUP BY
        UserId, DisplayName, Reputation, GoldBadgesCount, TotalPostsCreated
)
-- Main query: Combines segmented user data, applies a set operator (UNION ALL) for different cohorts, and final ranking.
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.UserCategory,
    ubs.CompositeEngagementScore,
    ubs.AggregatePostScore,
    ubs.TotalContentEdits,
    ubs.DuplicateClosedPosts,
    ubs.PostsWithExternalEdits,
    RANK() OVER (ORDER BY ubs.CompositeEngagementScore DESC, ubs.Reputation DESC) AS GlobalEngagementRank
FROM
    UserBehaviorSegmentation ubs
WHERE
    ubs.UserCategory IN ('High-Achiever Elite', 'Established Contributor')
    AND ubs.TotalContentEdits >= 5
    AND ubs.OverallUserAnswerAcceptanceRatio IS NOT NULL AND ubs.OverallUserAnswerAcceptanceRatio > 0.5 -- Only consider users with meaningful acceptance ratios
    AND NOT EXISTS ( -- Correlated subquery: Users who have never posted an answer to their own question
        SELECT 1
        FROM Posts p_q
        WHERE p_q.OwnerUserId = ubs.UserId
          AND p_q.PostTypeId = 1
          AND EXISTS (
            SELECT 1
            FROM Posts p_a
            WHERE p_a.ParentId = p_q.Id
              AND p_a.OwnerUserId = ubs.UserId
              AND p_a.PostTypeId = 2
          )
    )

UNION ALL

SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.UserCategory,
    ubs.CompositeEngagementScore,
    ubs.AggregatePostScore,
    ubs.TotalContentEdits,
    ubs.DuplicateClosedPosts,
    ubs.PostsWithExternalEdits,
    RANK() OVER (ORDER BY ubs.CompositeEngagementScore DESC, ubs.Reputation DESC) AS GlobalEngagementRank
FROM
    UserBehaviorSegmentation ubs
WHERE
    ubs.UserCategory IN ('Active Contributor', 'Emerging Participant')
    AND ubs.DuplicateClosedPosts > 0
    AND ubs.PostsWithExternalEdits >= 1
    AND ubs.Reputation < 5000
    AND ubs.AvgDaysBetweenPosts < 30 -- Frequent posters despite potential issues
    AND ubs.TotalCodeBlocksInPosts >= 3 -- Users contributing code examples
ORDER BY
    GlobalEngagementRank ASC, Reputation DESC
LIMIT 500;
