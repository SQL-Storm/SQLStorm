-- {"query": "1178.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3201} 

WITH UserAccountMetrics AS (
    -- CTE 1: Calculates fundamental user statistics, including account age, reputation categorization, and badge counts.
    -- It also uses an NTILE window function for reputation decile and a redundant (for demonstration) PARTITION BY window function.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        DATE_PART('day', CURRENT_DATE - u.CreationDate) AS AccountAgeDays, -- Calculation for account age
        u.Views AS ProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgesCount, -- Complex aggregate for badge counts
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgesCount,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationDecile, -- Window function: NTILE for user segmentation
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legendary Contributor'
            WHEN u.Reputation >= 25000 THEN 'Highly Esteemed'
            WHEN u.Reputation >= 5000 THEN 'Established Expert'
            WHEN u.Reputation >= 1000 THEN 'Active Participant'
            ELSE 'Newcomer'
        END AS ReputationTierName, -- Categorical expression
        MAX(u.LastAccessDate) OVER (PARTITION BY u.Id) AS LastAccessed -- Window function: MAX OVER PARTITION (demonstrative)
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId -- Outer join for badges
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementSummary AS (
    -- CTE 2: Aggregates post-level metrics such as scores, view counts, comment details, and includes tag parsing.
    -- It features correlated subqueries and a RANK window function.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount AS QuestionAnswerCount, -- Relevant only for PostTypeId = 1
        p.FavoriteCount AS QuestionFavoriteCount, -- Relevant only for PostTypeId = 1
        COALESCE(LENGTH(p.Body), 0) AS BodyLength, -- NULL logic, string expression
        LENGTH(p.Title) AS TitleLength, -- String expression
        REPLACE(LOWER(TRIM(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2))), '><', ',') AS CleanedTags, -- Complex string manipulation
        AVG(c.Score) AS AverageCommentScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnPost,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer, -- Boolean expression for acceptance
        NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived, -- NULLIF for zero upvotes, conditional aggregation
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = p.Id
              AND ans.PostTypeId = 2
              AND ans.OwnerUserId = p.OwnerUserId -- Correlated subquery: average score of answers by the question owner
        ) AS AvgSelfAnswerScoreOnQuestion,
        RANK() OVER (PARTITION BY p.PostTypeId, DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS PostMonthlyRank -- Window function: RANK
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId -- Outer join for comments
    LEFT JOIN Votes v ON p.Id = v.PostId -- Outer join for votes
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Body, p.Title, p.Tags, p.AcceptedAnswerId
),
UserHistoricalActions AS (
    -- CTE 3: Tracks various historical actions by users from PostHistory, including edits, close/reopen votes, and bounty starts.
    -- It also utilizes correlated subqueries and a LAG window function.
    SELECT
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditsMade, -- Conditional count for specific history types
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN ph.Id END) AS TotalCloseVotesCast,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11) THEN ph.Id END) AS TotalReopenVotesCast,
        MAX(ph.CreationDate) AS LatestHistoryActivity,
        LAG(MAX(ph.CreationDate)) OVER (PARTITION BY ph.UserId ORDER BY MAX(ph.CreationDate)) AS PreviousHistoryActivityDate, -- Window function: LAG for sequential comparison
        (
            SELECT COUNT(DISTINCT v_sub.Id)
            FROM Votes v_sub
            WHERE v_sub.UserId = ph.UserId AND v_sub.VoteTypeId = 8 -- Correlated subquery: count of bounties started by user
        ) AS BountiesStarted,
        (
            SELECT COUNT(DISTINCT pl.Id)
            FROM PostLinks pl
            WHERE pl.RelatedPostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ph.UserId)
            AND pl.LinkTypeId = 3 -- Correlated subquery: count of posts linked as duplicates TO user's posts
        ) AS LinkedAsDuplicatesCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TopQuestionTags AS (
    -- CTE 4: Identifies the top 10 most influential tags based on highly-scored and well-answered questions.
    -- It uses UNNEST and string_to_array for advanced tag parsing. This acts as an uncorrelated subquery result.
    SELECT
        tag_name,
        COUNT(PostId) AS TaggedQuestionCount,
        SUM(PostScore) AS TotalTagScore
    FROM (
        SELECT
            pe.PostId,
            pe.PostScore,
            UNNEST(string_to_array(SUBSTRING(pe.CleanedTags FROM 1 FOR LENGTH(pe.CleanedTags)), ',')) AS tag_name -- String to array, then unnest for multi-value field
        FROM PostEngagementSummary pe
        WHERE pe.PostTypeId = 1 AND pe.PostScore > 50 AND pe.QuestionAnswerCount > 5
    ) AS TaggedPosts
    WHERE tag_name IS NOT NULL AND tag_name <> ''
    GROUP BY tag_name
    ORDER BY TotalTagScore DESC, TaggedQuestionCount DESC
    LIMIT 10
),
UsersWithCommentsButNoPosts AS (
    -- CTE 5: Uses a set operator (EXCEPT) to find users who have commented on posts but have never owned any posts themselves.
    SELECT DISTINCT c.UserId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    EXCEPT
    SELECT DISTINCT p.OwnerUserId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
-- Main Query: Combines all CTEs to generate a comprehensive report on influential users and their content.
-- It includes complex joins, filtering, aggregation, and additional window functions (LAG, LEAD).
SELECT
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationTierName,
    uam.GoldBadgesCount,
    uam.SilverBadgesCount,
    uam.BronzeBadgesCount,
    uam.AccountAgeDays,
    uam.ProfileViews,
    uam.TotalUpVotesGiven,
    uam.TotalDownVotesGiven,
    SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwnedCount,
    SUM(CASE WHEN pes.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwnedCount,
    SUM(pes.PostScore) AS TotalPostsScore,
    SUM(pes.PostViewCount) AS TotalPostsViewCount,
    AVG(pes.AverageCommentScore) AS OverallAvgCommentScore,
    SUM(pes.TotalCommentsOnPost) AS TotalCommentsReceivedOnPosts,
    MAX(pes.LastCommentDate) AS LatestCommentReceived,
    AVG(pes.AvgSelfAnswerScoreOnQuestion) AS AvgSelfAnswerScoreAcrossOwnQuestions,
    COALESCE(SUM(pes.UpVotesReceived), 0) AS TotalUpVotesReceivedOnPosts, -- NULL handling with COALESCE
    COALESCE(SUM(pes.DownVotesReceived), 0) AS TotalDownVotesReceivedOnPosts,
    SUM(CASE WHEN pes.HasAcceptedAnswer THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    COALESCE(ROUND(CAST(SUM(CASE WHEN pes.HasAcceptedAnswer THEN 1 ELSE 0 END) AS NUMERIC) * 100 / NULLIF(SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 2), 0) AS QuestionAcceptanceRate, -- Complex calculation with NULLIF
    MAX(uha.TotalEditsMade) AS UserTotalEditsMade,
    MAX(uha.TotalCloseVotesCast) AS UserTotalCloseVotesCast,
    MAX(uha.LatestHistoryActivity) AS UserLatestHistoricalAction,
    (
        SELECT COUNT(DISTINCT tqa.tag_name)
        FROM TopQuestionTags tqa
        WHERE tqa.tag_name IN (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) FROM Posts p WHERE p.OwnerUserId = uam.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL)
    ) AS PopularTagsUsedCount, -- Correlated subquery using the TopQuestionTags CTE
    (
        SELECT COUNT(DISTINCT v_sub.Id)
        FROM Votes v_sub
        WHERE v_sub.UserId = uam.UserId AND v_sub.CreationDate > CURRENT_DATE - INTERVAL '1 year'
        AND v_sub.VoteTypeId IN (2,3) -- Uncorrelated subquery (conceptually) for recent vote activity by the user
    ) AS RecentVotesByThisUser,
    MAX(CASE WHEN uam.UserId IN (SELECT * FROM UsersWithCommentsButNoPosts) THEN TRUE ELSE FALSE END) AS IsCommenterOnly, -- Check against the set operator CTE
    LAG(uam.Reputation) OVER (ORDER BY uam.Reputation DESC) AS PrevHigherReputationUserReputation, -- Window function: LAG
    LEAD(uam.Reputation) OVER (ORDER BY uam.Reputation DESC) AS NextLowerReputationUserReputation -- Window function: LEAD
FROM UserAccountMetrics uam
LEFT JOIN PostEngagementSummary pes ON uam.UserId = pes.OwnerUserId -- Outer join
LEFT JOIN UserHistoricalActions uha ON uam.UserId = uha.UserId -- Outer join
WHERE
    uam.Reputation >= 1000 -- Initial filtering on user reputation
    AND uam.GoldBadgesCount > 0 -- Predicate requiring at least one gold badge
    AND uam.AccountAgeDays > 365 -- Account older than 1 year
    AND uam.DisplayName IS NOT NULL AND uam.DisplayName <> '' -- String predicate and NULL check
    AND (uam.DisplayName LIKE 'A%' OR uam.DisplayName LIKE 'S%') -- Complex OR predicate on string
    AND EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = uam.UserId AND PostTypeId = 1 AND Score > 100) -- EXISTS subquery: user must have at least one highly-scored question
    AND (pes.PostMonthlyRank <= 5 OR pes.PostMonthlyRank IS NULL) -- Filtering on window function result for posts, handling NULL from LEFT JOIN
GROUP BY
    uam.UserId, uam.DisplayName, uam.Reputation, uam.ReputationTierName,
    uam.GoldBadgesCount, uam.SilverBadgesCount, uam.BronzeBadgesCount,
    uam.AccountAgeDays, uam.ProfileViews, uam.TotalUpVotesGiven, uam.TotalDownVotesGiven,
    uam.ReputationDecile -- Must be included in GROUP BY if selected
HAVING
    COUNT(DISTINCT pes.PostId) > 10 -- Aggregate condition: must have owned at least 10 posts
    AND SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END) >= 2 -- Aggregate condition: at least 2 questions
    AND COALESCE(SUM(pes.UpVotesReceived), 0) > 50 -- Aggregate condition: at least 50 upvotes received on posts
    AND COALESCE(AVG(pes.AverageCommentScore), 0) > 0.5 -- Aggregate condition: average comment score positive, NULL handling
ORDER BY
    uam.Reputation DESC, QuestionsOwnedCount DESC, TotalUpVotesReceivedOnPosts DESC
LIMIT 50;
