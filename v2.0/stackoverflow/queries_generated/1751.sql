-- {"query": "1751.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3571} 

WITH UserEngagement AS (
    -- Aggregates user-level metrics including badge counts using correlated subqueries
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreOwned,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViewsOwned,
        MAX(p.LastActivityDate) AS LastPostActivityOwned,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / (60 * 60 * 24)) AS AvgPostActivityDaysOwned,
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostEditActivitySummary AS (
    -- Summarizes editing activity for posts, calculating average time between edits
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        -- Calculate average hours between any two consecutive edits for the same post
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - prev_ph.CreationDate)) / 3600.0) AS AvgHoursBetweenEdits
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN LATERAL ( -- Lateral join to find the previous edit's creation date for the same post
        SELECT ph_inner.CreationDate
        FROM PostHistory ph_inner
        WHERE ph_inner.PostId = ph.PostId
          AND ph_inner.CreationDate < ph.CreationDate
          AND ph_inner.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback events
        ORDER BY ph_inner.CreationDate DESC
        LIMIT 1
    ) AS prev_ph ON TRUE
    WHERE pht.Name LIKE '%Edit Body%' OR pht.Name LIKE '%Edit Tags%' OR pht.Name LIKE '%Edit Title%'
    GROUP BY ph.PostId, ph.UserId -- Group by PostId and EditorUserId to get per-user-per-post edit summary
),
QuestionTagAndAcceptanceAnalysis AS (
    -- Analyzes questions for primary tag, tag count, and fast acceptance status
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1) AS PrimaryTag, -- Extracts the first tag
        ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'), 1) AS TagCount,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        -- Check if an answer was accepted within 7 days of question creation
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL AND
                 (SELECT a.CreationDate FROM Posts a WHERE a.Id = p.AcceptedAnswerId) IS NOT NULL AND
                 (SELECT a.CreationDate FROM Posts a WHERE a.Id = p.AcceptedAnswerId) <= p.CreationDate + INTERVAL '7 days'
            THEN TRUE
            ELSE FALSE
        END AS AcceptedFast
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
PostDetailsExtended AS (
    -- Combines post details with aggregated edit, vote, and comment information
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(pes.EditCount, 0) AS EditCount,
        pes.AvgHoursBetweenEdits,
        COALESCE(v_up.UpVotesReceived, 0) AS UpVotesReceived,
        COALESCE(v_down.DownVotesReceived, 0) AS DownVotesReceived,
        (SELECT MIN(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS FirstCommentDate,
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN PostEditActivitySummary pes ON p.Id = pes.PostId AND p.OwnerUserId = pes.EditorUserId -- Join for owner's edit activity
    LEFT JOIN (SELECT PostId, COUNT(Id) AS UpVotesReceived FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v_up ON p.Id = v_up.PostId
    LEFT JOIN (SELECT PostId, COUNT(Id) AS DownVotesReceived FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) v_down ON p.Id = v_down.PostId
),
UserPostAndActivityAggregates AS (
    -- Aggregates post-level metrics back to the user level, incorporating window functions and a correlated subquery
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.TotalUpVotesGiven,
        ue.TotalDownVotesGiven,
        ue.GoldBadges,
        ue.SilverBadges,
        ue.BronzeBadges,
        COUNT(pde.PostId) AS UserPostsWithDetails,
        SUM(pde.UpVotesReceived) AS UserTotalUpVotesReceived,
        SUM(pde.DownVotesReceived) AS UserTotalDownVotesReceived,
        AVG(pde.Score) AS UserAvgPostScore,
        AVG(pde.CommentCount) AS UserAvgCommentCount,
        AVG(pde.FavoriteCount) AS UserAvgFavoriteCount,
        -- Window function: Rank users by reputation within their badge class distribution
        RANK() OVER (ORDER BY ue.Reputation DESC, ue.GoldBadges DESC, ue.SilverBadges DESC) AS OverallReputationRank,
        -- Correlated subquery: Find the title of the user's highest-viewed question
        -- that was edited by a different user and has at least one answer.
        (
            SELECT p_sub.Title
            FROM Posts p_sub
            INNER JOIN PostHistory ph_sub ON p_sub.Id = ph_sub.PostId
            WHERE p_sub.OwnerUserId = ue.UserId
              AND p_sub.PostTypeId = 1 -- Question
              AND p_sub.AnswerCount >= 1
              AND ph_sub.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
              AND ph_sub.UserId IS NOT NULL
              AND ph_sub.UserId <> ue.UserId -- Edited by someone else
            ORDER BY p_sub.ViewCount DESC, p_sub.CreationDate ASC
            LIMIT 1
        ) AS TopViewedQuestionEditedByOthersTitle,
        -- Calculate a weighted activity score based on votes, favorites, and comments
        (SUM(pde.UpVotesReceived * 0.5) + SUM(pde.DownVotesReceived * -0.2) +
         SUM(pde.FavoriteCount * 1.0) + SUM(pde.CommentCount * 0.3)) AS UserWeightedActivityScore,
        AVG(pde.AvgHoursBetweenEdits) AS AvgHoursBetweenOwnPostEdits
    FROM UserEngagement ue
    LEFT JOIN PostDetailsExtended pde ON ue.UserId = pde.OwnerUserId
    GROUP BY ue.UserId, ue.DisplayName, ue.Reputation, ue.UserCreationDate, ue.TotalUpVotesGiven,
             ue.TotalDownVotesGiven, ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges
),
CombinedTopPostPerformance AS (
    -- Combines top questions and top answers using UNION ALL for comparative analysis
    -- Part 1: Top 100 questions by score with specific tags
    SELECT
        'Question' AS PostTypeCategory,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        qtaa.PrimaryTag AS MainTag,
        qtaa.AcceptedFast,
        p.CreationDate
    FROM Posts p
    INNER JOIN QuestionTagAndAcceptanceAnalysis qtaa ON p.Id = qtaa.PostId
    WHERE p.PostTypeId = 1
      AND p.Score > 50
      AND qtaa.PrimaryTag IN ('javascript', 'python', 'java', 'c#', 'sql') -- Filter for specific tags
    ORDER BY p.Score DESC, p.CreationDate DESC
    LIMIT 100
    UNION ALL
    -- Part 2: Top 100 answers by score that were accepted for a question with high views
    SELECT
        'Answer' AS PostTypeCategory,
        p.Id AS PostId,
        q.Title AS ParentQuestionTitle, -- Get parent question title for answers
        p.Score,
        q.ViewCount AS ParentQuestionViewCount, -- Use parent question's view count
        p.OwnerUserId,
        NULL AS MainTag, -- Answers don't have tags directly
        NULL AS AcceptedFast,
        p.CreationDate
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
      AND p.Score > 20
      AND q.ViewCount > 10000 -- Filter for answers to highly viewed questions
      AND q.AcceptedAnswerId = p.Id -- Ensure it's an accepted answer
    ORDER BY p.Score DESC, p.CreationDate DESC
    LIMIT 100
)
-- Final result set combining user and post performance metrics
SELECT
    uapa.UserId,
    COALESCE(uapa.DisplayName, 'Unknown User') AS DisplayName,
    uapa.Reputation,
    -- Categorize users into reputation tiers using a complex CASE expression
    CASE
        WHEN uapa.Reputation >= 50000 THEN 'Legendary Contributor'
        WHEN uapa.Reputation >= 10000 THEN 'Distinguished Expert'
        WHEN uapa.Reputation >= 2000 THEN 'Valued Contributor'
        WHEN uapa.Reputation >= 500 THEN 'Active Participant'
        ELSE 'Emerging User'
    END AS ReputationTier,
    uapa.UserCreationDate,
    uapa.TotalUpVotesGiven,
    uapa.TotalDownVotesGiven,
    uapa.UserTotalUpVotesReceived,
    uapa.UserTotalDownVotesReceived,
    uapa.UserAvgPostScore,
    uapa.UserAvgCommentCount,
    uapa.UserAvgFavoriteCount,
    uapa.GoldBadges,
    uapa.SilverBadges,
    uapa.BronzeBadges,
    uapa.OverallReputationRank,
    uapa.TopViewedQuestionEditedByOthersTitle,
    uapa.UserWeightedActivityScore,
    COALESCE(uapa.AvgHoursBetweenOwnPostEdits, 24.0 * 365) AS AvgHoursBetweenOwnPostEdits, -- Default to a large number if no edits
    ctpp.PostTypeCategory,
    ctpp.PostId AS TopPostId,
    COALESCE(ctpp.Title, ctpp.ParentQuestionTitle, 'N/A') AS TopPostTitle, -- Use ParentQuestionTitle for answers
    ctpp.Score AS TopPostScore,
    ctpp.MainTag AS TopPostMainTag,
    ctpp.AcceptedFast AS TopQuestionAcceptedFast,
    -- Window function: Calculate the moving average of user's reputation based on their creation date
    AVG(uapa.Reputation) OVER (ORDER BY uapa.UserCreationDate ASC ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS MovingAvgReputation10Users,
    -- Window function: Rank posts by their score within their category and main tag
    ROW_NUMBER() OVER (PARTITION BY ctpp.PostTypeCategory, ctpp.MainTag ORDER BY ctpp.Score DESC, ctpp.CreationDate DESC) AS PostRankWithinCategoryTag,
    -- Calculate a comprehensive user complexity/engagement score
    (uapa.UserTotalUpVotesReceived * 0.15 + uapa.UserTotalDownVotesReceived * -0.07 +
     uapa.UserAvgPostScore * 0.25 + uapa.UserAvgCommentCount * 0.18 +
     uapa.GoldBadges * 8 + uapa.SilverBadges * 3 + uapa.BronzeBadges * 0.8 +
     (CASE WHEN uapa.AvgHoursBetweenOwnPostEdits IS NULL THEN -50.0 ELSE (1000 / uapa.AvgHoursBetweenOwnPostEdits) * 0.1 END) +
     (uapa.TotalQuestionsOwned * 0.05 + uapa.TotalAnswersOwned * 0.07) +
     (CASE WHEN uapa.TopViewedQuestionEditedByOthersTitle IS NOT NULL THEN 10.0 ELSE 0.0 END)
    ) AS UserComplexityAndEngagementScore
FROM UserPostAndActivityAggregates uapa
LEFT JOIN CombinedTopPostPerformance ctpp ON uapa.UserId = ctpp.OwnerUserId
WHERE
    uapa.Reputation > 200 -- Focus on more established users
    AND uapa.UserPostsWithDetails > 3 -- Users with significant post count
    AND (uapa.GoldBadges > 0 OR uapa.SilverBadges > 0 OR uapa.BronzeBadges > 2) -- Users with some notable badges
    AND uapa.UserCreationDate >= '2015-01-01' -- Filter for more recent activity
ORDER BY
    UserComplexityAndEngagementScore DESC,
    uapa.OverallReputationRank ASC,
    uapa.UserCreationDate DESC,
    ctpp.PostId DESC
LIMIT 1000;
