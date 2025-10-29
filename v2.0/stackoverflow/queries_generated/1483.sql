-- {"query": "1483.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3363} 

WITH UserTopTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT tag_val, ', ' ORDER BY tag_val) AS TopTagsString,
        COUNT(DISTINCT tag_val) AS UniqueTagsCount
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_val
    WHERE p.Tags IS NOT NULL
      AND p.PostTypeId = 1 -- Only consider questions for tags
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT tag_val) > 0
),
UserPostPerformance AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2) AND p.Score > 0) AS AvgPositivePostScore,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCount,
        SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedPosts,
        -- Calculate average days to first edit for user's posts
        AVG(EXTRACT(EPOCH FROM (ph_first_edit.CreationDate - p.CreationDate)) / (60*60*24)) AS AvgDaysToFirstEdit
    FROM Posts p
    LEFT JOIN (
        SELECT
            ph.PostId,
            MIN(ph.CreationDate) AS CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        GROUP BY ph.PostId
    ) AS ph_first_edit ON p.Id = ph_first_edit.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsWritten,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(LENGTH(c.Text)) AS MaxCommentLength,
        -- Correlated subquery example: Check if user has any comment with a specific phrase
        CASE
            WHEN EXISTS (SELECT 1 FROM Comments c2 WHERE c2.UserId = c.UserId AND c2.Text ILIKE '%great answer%' LIMIT 1)
            THEN 'Praiser'
            WHEN EXISTS (SELECT 1 FROM Comments c3 WHERE c3.UserId = c.UserId AND c3.Text ILIKE '%bug%' LIMIT 1)
            THEN 'Bug Reporter'
            ELSE 'Normal Commenter'
        END AS CommenterCategory
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.Class = 1 AND b.TagBased = TRUE THEN 1 ELSE 0 END) AS GoldTagBadges,
        SUM(CASE WHEN b.Class = 2 AND b.TagBased = FALSE THEN 1 ELSE 0 END) AS SilverNamedBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostClosureAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS UniqueClosedPosts,
        COUNT(ph.Id) AS TotalCloseEvents,
        STRING_AGG(DISTINCT crt.Name, '; ' ORDER BY crt.Name) AS DistinctCloseReasonsEncountered
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment::smallint = crt.Id -- Assuming Comment stores CloseReasonId for type 10
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserInfluenceRanking AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views AS ProfileViews,
        u.UpVotes,
        u.DownVotes,
        COALESCE(upp.TotalPosts, 0) AS TotalPosts,
        COALESCE(upp.QuestionsCount, 0) AS QuestionsCount,
        COALESCE(upp.AnswersCount, 0) AS AnswersCount,
        COALESCE(upp.AvgPositivePostScore, 0.0) AS AvgPositivePostScore,
        COALESCE(uca.TotalCommentsWritten, 0) AS TotalCommentsWritten,
        COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadgesCount,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadgesCount,
        COALESCE(pca.UniqueClosedPosts, 0) AS UniqueClosedPostsCount,
        COALESCE(pca.TotalCloseEvents, 0) AS PostClosedEvents,
        pca.DistinctCloseReasonsEncountered,
        utt.TopTagsString,
        utt.UniqueTagsCount,
        uca.CommenterCategory,
        u.UpVotes * 1.0 / NULLIF(u.DownVotes, 0) AS UpDownVoteRatio,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60*60*24) AS DaysSinceAccountCreation,
        COALESCE(upp.AvgDaysToFirstEdit, 0.0) AS AvgDaysToFirstEdit,
        -- Weighted Influence Score: Incorporating various factors with specific weights
        (
            u.Reputation * 0.1
            + COALESCE(upp.AvgPositivePostScore, 0) * 0.5
            + COALESCE(upp.TotalPosts, 0) * 0.01
            + COALESCE(uca.TotalCommentsWritten, 0) * 0.005
            + COALESCE(ubs.GoldBadges, 0) * 50
            + COALESCE(ubs.SilverBadges, 0) * 10
            - COALESCE(pca.TotalCloseEvents, 0) * 20 -- Negative impact of posts being closed
            + (SELECT COALESCE(SUM(v.BountyAmount), 0) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) * 0.1 -- Bounty Giver influence
            + (SELECT COALESCE(SUM(v.BountyAmount), 0) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 9) * 0.05 -- Bounty Earner influence (lower weight)
            + (u.UpVotes - u.DownVotes) * 0.001 -- Net votes contribution
        ) AS InfluenceScore,
        -- Correlated Subquery: Count recent high-view questions by the user
        (SELECT COUNT(DISTINCT p_recent.Id)
         FROM Posts p_recent
         WHERE p_recent.OwnerUserId = u.Id
           AND p_recent.PostTypeId = 1
           AND p_recent.ViewCount > 50000 -- Very high view count threshold
           AND p_recent.CreationDate >= (NOW() - INTERVAL '1 year')) AS RecentHighViewQuestionsCount,
        -- Correlated Subquery: Count old posts that were edited significantly late compared to user's average
        (SELECT COUNT(DISTINCT p_old.Id)
         FROM Posts p_old
         WHERE p_old.OwnerUserId = u.Id
           AND p_old.PostTypeId IN (1,2)
           AND p_old.CreationDate < (NOW() - INTERVAL '2 years') -- Posts older than 2 years
           AND upp.AvgDaysToFirstEdit IS NOT NULL -- Only consider if user has any edited posts
           AND (EXTRACT(EPOCH FROM (COALESCE(p_old.LastEditDate, p_old.CreationDate) - p_old.CreationDate)) / (60*60*24)) > (upp.AvgDaysToFirstEdit * 2)
        ) AS OldPostsEditedLateCount,
        -- Check if user is a "community owner" of many posts (contributed to posts becoming community wiki)
        (SELECT COUNT(DISTINCT ph_comm.PostId)
         FROM PostHistory ph_comm
         WHERE ph_comm.UserId = u.Id
           AND ph_comm.PostHistoryTypeId = 16) AS CommunityOwnedInitiations
    FROM Users u
    LEFT JOIN UserPostPerformance upp ON u.Id = upp.UserId
    LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
    LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
    LEFT JOIN PostClosureAnalysis pca ON u.Id = pca.UserId
    LEFT JOIN UserTopTags utt ON u.Id = utt.UserId
    WHERE u.Reputation > 5000 -- Filter for significantly active users
      AND u.DisplayName IS NOT NULL AND LENGTH(TRIM(u.DisplayName)) > 0
      AND u.LastAccessDate >= (NOW() - INTERVAL '6 months') -- Recently active users
)
SELECT
    uir.UserId,
    uir.DisplayName,
    uir.Reputation,
    uir.ProfileViews,
    uir.TotalPosts,
    uir.QuestionsCount,
    uir.AnswersCount,
    uir.AvgPositivePostScore,
    uir.TotalCommentsWritten,
    uir.AvgCommentScore,
    uir.GoldBadgesCount,
    uir.SilverBadgesCount,
    uir.UniqueClosedPostsCount,
    uir.PostClosedEvents,
    uir.DistinctCloseReasonsEncountered,
    uir.TopTagsString,
    uir.UniqueTagsCount,
    uir.CommenterCategory,
    uir.InfluenceScore,
    uir.RecentHighViewQuestionsCount,
    uir.OldPostsEditedLateCount,
    uir.CommunityOwnedInitiations,
    -- Window Function: Rank users by their InfluenceScore
    RANK() OVER (ORDER BY uir.InfluenceScore DESC, uir.Reputation DESC, uir.TotalPosts DESC) AS InfluenceRank,
    -- Window Function: Calculate average reputation of users in the same 'reputation bracket' (e.g., thousands)
    AVG(uir.Reputation) OVER (PARTITION BY FLOOR(uir.Reputation / 10000)) AS AvgReputationInBracket,
    -- Window Function: Difference in influence score from the next higher ranked user
    uir.InfluenceScore - LEAD(uir.InfluenceScore, 1, 0) OVER (ORDER BY uir.InfluenceScore DESC) AS InfluenceScoreDiffToNext,
    -- Window Function: Percentage of posts that are answers compared to total posts for the user, relative to overall average
    (uir.AnswersCount * 100.0 / NULLIF(uir.TotalPosts, 0)) - AVG(uir.AnswersCount * 100.0 / NULLIF(uir.TotalPosts, 0)) OVER () AS AnswerPostRatioDeviation,
    -- String Expression: Format creation date and calculate age in years
    TO_CHAR(uir.CreationDate, 'YYYY-MM-DD HH24:MI') AS FormattedCreationDate,
    TRUNC(uir.DaysSinceAccountCreation / 365.25) || ' years' AS AccountAge,
    -- Complicated Predicate/Expression: Categorize users based on account age and recent activity
    CASE
        WHEN uir.DaysSinceAccountCreation > 365 * 10 AND uir.LastAccessDate >= (NOW() - INTERVAL '3 months') THEN 'Ancient Active Guru'
        WHEN uir.DaysSinceAccountCreation > 365 * 5 AND uir.LastAccessDate >= (NOW() - INTERVAL '6 months') THEN 'Veteran Active Contributor'
        WHEN uir.DaysSinceAccountCreation < 365 * 1 AND uir.TotalPosts > 10 AND uir.Reputation > 1000 THEN 'Promising Newcomer'
        ELSE 'Regular Member'
    END AS UserActivityTier,
    -- NULL Logic/Conditional calculation: Up/Down Vote Ratio description
    COALESCE(
        CASE
            WHEN uir.UpDownVoteRatio > 20 THEN 'Extremely Positive'
            WHEN uir.UpDownVoteRatio > 5 THEN 'Highly Positive'
            WHEN uir.UpDownVoteRatio >= 1 THEN 'Mostly Positive'
            WHEN uir.UpDownVoteRatio < 1 AND uir.UpDownVoteRatio > 0 THEN 'Slightly Negative'
            WHEN uir.UpDownVoteRatio = 0 THEN 'Only Downvotes'
            ELSE NULL -- Should not happen with NULLIF, but good for completeness
        END, 'No Downvotes Recorded') AS VoteRatioDescription,
    -- Conditional check for users who might be primarily question-askers or answerers
    CASE
        WHEN uir.QuestionsCount * 1.0 / NULLIF(uir.AnswersCount, 0) > 5 AND uir.QuestionsCount > 10 THEN 'Primary Questioner'
        WHEN uir.AnswersCount * 1.0 / NULLIF(uir.QuestionsCount, 0) > 5 AND uir.AnswersCount > 10 THEN 'Primary Answerer'
        ELSE 'Balanced Contributor'
    END AS ContributionStyle
FROM UserInfluenceRanking uir
WHERE uir.InfluenceScore > 1000 -- Filter for genuinely high-influence users
  AND uir.GoldBadgesCount > 0 -- Must have at least one gold badge
  AND uir.UniqueTagsCount >= 2 -- Engaged in at least two distinct topics
ORDER BY InfluenceRank ASC, uir.UserId ASC
LIMIT 200;
