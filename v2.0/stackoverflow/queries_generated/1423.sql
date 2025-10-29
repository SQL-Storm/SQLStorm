-- {"query": "1423.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3266} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCounts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpvotesGiven, -- UpMod votes by user
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownvotesGiven, -- DownMod votes by user
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        ARRAY_AGG(DISTINCT SUBSTRING(t.TagName, 1, 10)) FILTER (WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL) AS UserQuestionTags_Sample
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId -- Votes cast by the user
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%' -- simplistic tag matching, highly inefficient but for benchmarking
    GROUP BY u.Id
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoricalMetrics AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseVoteHistoryCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenVoteHistoryCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
QuestionAnswerEngagement AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.ViewCount,
        q.FavoriteCount,
        COUNT(DISTINCT ans.Id) AS AnswerCount,
        COALESCE(AVG(ans.Score), 0) AS AvgAnswerScore,
        -- Complex calculation: Average number of '<code>' blocks per answer
        COALESCE(SUM(LENGTH(ans.Body) - LENGTH(REPLACE(ans.Body, '<code>', ''))) / NULLIF(COUNT(ans.Id) * LENGTH('<code>'), 0), 0) AS AvgAnswerCodeBlocks,
        (
            SELECT MAX(pl.CreationDate)
            FROM PostLinks pl
            WHERE pl.PostId = q.Id
            AND pl.LinkTypeId = 1 -- Linked
        ) AS LastLinkedDate,
        (
            SELECT COUNT(DISTINCT co.UserId)
            FROM Comments co
            WHERE co.PostId = q.Id
            AND co.UserId IS NOT NULL
        ) AS DistinctCommenterCount_Question
    FROM Posts q
    LEFT JOIN Posts ans ON q.Id = ans.ParentId AND ans.PostTypeId = 2
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.ViewCount, q.FavoriteCount
),
TopTagsByPostCount AS (
    SELECT
        TRIM(REPLACE(SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', s.a), '>', '')) AS TagName,
        COUNT(t.Id) AS PostCount
    FROM Posts t
    -- Lateral join to explode tags string into rows
    CROSS JOIN LATERAL GENERATE_SERIES(1, LENGTH(t.Tags) - LENGTH(REPLACE(t.Tags, '><', '')) + 1) AS s(a)
    WHERE t.Tags IS NOT NULL AND t.PostTypeId = 1
    GROUP BY TRIM(REPLACE(SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', s.a), '>', ''))
    HAVING COUNT(t.Id) > 500 -- only consider tags with sufficient posts
    ORDER BY COUNT(t.Id) DESC
    LIMIT 100
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(uas.TotalPosts, 0) AS TotalPosts,
    COALESCE(uas.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(uas.TotalPostScore, 0) AS TotalScoreFromPosts,
    COALESCE(uas.TotalPostViews, 0) AS TotalViewsForUserPosts,
    COALESCE(uas.TotalFavoriteCounts, 0) AS TotalFavoritesOnUserPosts,
    COALESCE(uas.TotalComments, 0) AS TotalCommentsMade,
    COALESCE(uas.TotalUpvotesGiven, 0) AS TotalUpvotesCast,
    COALESCE(uas.TotalDownvotesGiven, 0) AS TotalDownvotesCast,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    (EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24))::int AS DaysSinceCreation, -- User Age in Days
    -- Correlated Subquery: Get average score of posts by users created in the same month/year
    (
        SELECT AVG(p_corr.Score)
        FROM Posts p_corr
        JOIN Users u_corr ON p_corr.OwnerUserId = u_corr.Id
        WHERE EXTRACT(YEAR FROM u_corr.CreationDate) = EXTRACT(YEAR FROM u.CreationDate)
          AND EXTRACT(MONTH FROM u_corr.CreationDate) = EXTRACT(MONTH FROM u.CreationDate)
          AND p_corr.PostTypeId IN (1, 2)
    ) AS AvgScoreSameCreationMonthUsers,
    -- Window functions for ranking and comparison
    RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY u.UpVotes DESC, u.CreationDate ASC) AS UpVoteDecile,
    LAG(u.Reputation, 1, 0) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS PrevUserRepInYear,
    LEAD(u.Reputation, 1, 0) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS NextUserRepInYear,
    -- Complex expression for "User Engagement Ratio"
    ROUND(
        COALESCE(
            (uas.TotalUpvotesGiven + uas.TotalDownvotesGiven + uas.TotalComments + uas.TotalPosts) /
            NULLIF(uas.TotalPostViews + u.Views, 0.0),
            0.0
        )::numeric, 4
    ) AS UserEngagementRatio,
    -- String manipulations and NULL logic
    COALESCE(LENGTH(u.AboutMe), 0) AS AboutMeLength,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND LOWER(u.WebsiteUrl) LIKE '%linkedin.com%' THEN 'Has LinkedIn Profile'
        WHEN u.WebsiteUrl IS NOT NULL AND LOWER(u.WebsiteUrl) LIKE '%.com%' THEN 'Has .com Website'
        WHEN u.WebsiteUrl IS NOT NULL AND LOWER(u.WebsiteUrl) LIKE '%.org%' THEN 'Has .org Website'
        WHEN u.WebsiteUrl IS NOT NULL THEN 'Has Other Website'
        ELSE 'No Website'
    END AS WebsiteCategory,
    -- Aggregated data from QuestionAnswerEngagement (only for questions owned by this user)
    SUM(COALESCE(qae.AnswerCount, 0)) AS TotalAnswersToUserQuestions,
    AVG(COALESCE(qae.AvgAnswerScore, 0)) AS AvgAnswerScoreToUserQuestions,
    -- Further joins and aggregations on specific posts (q here represents any post by the user, for conditional aggregation)
    MAX(CASE WHEN q.PostTypeId = 1 AND q.Score > 50 AND q.ViewCount > 1000 THEN q.CreationDate ELSE NULL END) AS LatestHighlyEngagedQuestionDate,
    SUM(CASE WHEN q.PostTypeId = 1 AND q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
    SUM(COALESCE(phm.EditCount, 0)) AS TotalEditsOnUserPosts, -- Total edits across all user's posts
    -- Set operator (INTERSECT) within a scalar subquery: Count questions by this user that are both 'questions' AND have > 1000 views
    (
        SELECT COUNT(DISTINCT posts_inter.Id)
        FROM (
            SELECT p_i.Id FROM Posts p_i WHERE p_i.OwnerUserId = u.Id AND p_i.PostTypeId = 1 -- Questions by user
            INTERSECT
            SELECT p_v.Id FROM Posts p_v WHERE p_v.OwnerUserId = u.Id AND p_v.ViewCount > 1000 -- High view posts by user
        ) AS posts_inter
    ) AS HighViewQuestionsBySetOpCount,
    -- Complicated Predicate: Count recent high-score questions by the user, avoiding less popular tags
    (
        SELECT COUNT(DISTINCT q_comp.Id)
        FROM Posts q_comp
        WHERE q_comp.OwnerUserId = u.Id
          AND q_comp.PostTypeId = 1
          AND q_comp.CreationDate >= u.LastAccessDate - INTERVAL '1 year'
          AND q_comp.Score > (SELECT AVG(p_avg.Score) FROM Posts p_avg WHERE p_avg.PostTypeId = 1)
          AND NOT EXISTS (
              SELECT 1 FROM TopTagsByPostCount tt
              WHERE q_comp.Tags LIKE '%' || tt.TagName || '%' AND tt.PostCount < 5000 -- Exclude questions from less popular top tags
          )
    ) AS RecentHighScoreQuestions_ComplexTagFilter,
    -- Nested subquery: Boolean flag for users with a highly engaged question (answered, multiple comments, linked)
    (
        SELECT
            CASE WHEN EXISTS (
                SELECT 1
                FROM Posts q_n
                WHERE q_n.OwnerUserId = u.Id
                  AND q_n.PostTypeId = 1
                  AND q_n.AcceptedAnswerId IS NOT NULL -- Question has an accepted answer
                  AND (SELECT COUNT(DISTINCT c_n.UserId) FROM Comments c_n WHERE c_n.PostId = q_n.Id) >= 2 -- At least 2 distinct commenters
                  AND EXISTS (SELECT 1 FROM PostLinks pl_n WHERE pl_n.PostId = q_n.Id AND pl_n.LinkTypeId = 1) -- Is linked to another post
                  AND q_n.LastActivityDate > NOW() - INTERVAL '6 months' -- Recent activity
            ) THEN TRUE ELSE FALSE END
    ) AS HasHighlyEngagedRecentQuestion
FROM Users u
LEFT JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN Posts q ON u.Id = q.OwnerUserId -- Join for conditional aggregations over ALL posts by the user
LEFT JOIN PostHistoricalMetrics phm ON q.Id = phm.PostId -- Join for post historical metrics for ALL posts by the user
LEFT JOIN QuestionAnswerEngagement qae ON u.Id = qae.OwnerUserId AND q.Id = qae.QuestionId -- Join specific questions to QAE
WHERE u.Reputation >= 500 -- Filter for more active users
  AND u.CreationDate BETWEEN '2010-01-01' AND '2022-12-31'
  AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL) -- NULL logic in predicate
  AND (
        u.LastAccessDate > NOW() - INTERVAL '1 year'
        OR u.UpVotes > 500
        OR uas.TotalPosts > 50
      ) -- Active or impactful users
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes,
    uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalPostScore, uas.TotalPostViews,
    uas.TotalFavoriteCounts, uas.TotalComments, uas.TotalUpvotesGiven, uas.TotalDownvotesGiven,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
ORDER BY ReputationRank, UserEngagementRatio DESC, u.CreationDate
LIMIT 2000;