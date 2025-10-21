-- {"query": "19053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3924} 

WITH UserPostStats AS (
    -- Aggregate statistics for posts created by each user
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViewCount,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        -- Calculate average post age at last activity for users, in days
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / (60 * 60 * 24)) AS AvgPostAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
UserCommentStats AS (
    -- Aggregate statistics for comments made by each user
    SELECT
        u.Id AS UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
UserBadgeSummary AS (
    -- Summarize badge counts by class for each user
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostHistoryMetrics AS (
    -- Calculate various metrics from post history for each post
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryTypes,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS RollbackCount, -- Title, Body, Tags rollbacks
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserPostHistoryAggregates AS (
    -- Aggregate post history metrics for each user across all their posts
    SELECT
        p.OwnerUserId AS UserId,
        AVG(phm.EditCount) AS AvgPostEditCount,
        MAX(phm.CloseCount) AS MaxPostCloseCountPerUser,
        MAX(phm.LastHistoryDate) AS LastHistoryDatePerUser,
        COUNT(DISTINCT p.Id) FILTER (WHERE phm.CloseCount > 0 OR phm.ReopenCount > 0 OR phm.RollbackCount > 0) AS ControversialPostsCount
    FROM Posts p
    JOIN PostHistoryMetrics phm ON p.Id = phm.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPostTagAggregates AS (
    -- Aggregate tag usage and average score for posts by each user
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScoreForTagPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    -- Deconstruct tags string into individual tags
    JOIN LATERAL UNNEST(string_to_array(TRIM(REPLACE(REPLACE(p.Tags, '<', ''), '>', ' ')), ' ')) AS t(TagName) ON t.TagName IS NOT NULL AND t.TagName != ''
    WHERE p.PostTypeId = 1 -- Only consider questions for tag aggregates
    GROUP BY u.Id, t.TagName
)
( -- Start of Query Branch 1: High Reputation and Active Users
SELECT
    u.Id AS UserID,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.QuestionCount, 0) AS QuestionCount,
    COALESCE(ups.AnswerCount, 0) AS AnswerCount,
    COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(ups.AvgPostViewCount, 0) AS AvgPostViewCount,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(upha.AvgPostEditCount, 0) AS AvgPostEditCountPerUser,
    COALESCE(upha.MaxPostCloseCountPerUser, 0) AS MaxPostCloseCountPerUser,
    COALESCE(upha.ControversialPostsCount, 0) AS ControversialPostsCount,
    -- Correlated Subquery: average score of user's posts that are not questions
    (
        SELECT COALESCE(AVG(p_corr.Score), 0)
        FROM Posts p_corr
        WHERE p_corr.OwnerUserId = u.Id
          AND p_corr.PostTypeId <> 1 -- Non-question posts
          AND p_corr.CreationDate BETWEEN u.CreationDate AND u.LastAccessDate
          AND p_corr.Score IS NOT NULL
    ) AS AvgCorrelatedPostScore,
    -- Window Function: Rank users by a combined activity score
    RANK() OVER (
        ORDER BY
            u.Reputation DESC,
            COALESCE(ups.TotalPostScore, 0) DESC,
            (COALESCE(ubs.GoldBadges, 0) * 10 + COALESCE(ubs.SilverBadges, 0) * 5 + COALESCE(ubs.BronzeBadges, 0)) DESC
    ) AS UserRankScore,
    -- Second Window Function: Previous user's access date within the same location
    COALESCE(LAG(u.LastAccessDate, 1, u.CreationDate) OVER (PARTITION BY u.Location ORDER BY u.CreationDate)::text, 'N/A') AS WindowFuncOutput_Text,
    -- String Aggregate: Top tags of interest for the user
    COALESCE(STRING_AGG(upt.TagName, ', ') FILTER (WHERE upt.PostsWithTag > 5 AND upt.AvgScoreForTagPosts > 10), 'No Top Tags') AS AggregatedTagsString,
    -- Complex Calculation/Persona Classifier: Categorize users based on various metrics
    CASE
        WHEN u.Reputation > 50000 AND COALESCE(ubs.GoldBadges,0) >= 5 AND COALESCE(ups.QuestionCount,0) >= 50 THEN 'Guru'
        WHEN u.Reputation > 10000 AND COALESCE(ubs.SilverBadges,0) >= 10 THEN 'Expert'
        WHEN u.Reputation > 1000 AND COALESCE(ucs.TotalComments,0) > 100 AND COALESCE(ups.AnswerCount,0) > 50 THEN 'Contributor'
        ELSE 'Casual'
    END AS UserPersonaClassifier,
    -- String Expression: Calculate processed length of AboutMe, replacing common terms
    LENGTH(COALESCE(REPLACE(REPLACE(u.AboutMe, 'Stack Overflow', 'SO'), 'database', 'DB'), '')) AS AboutMeStringMetric,
    -- NULL Logic combined with date arithmetic: Days since last significant activity
    (u.LastAccessDate - COALESCE(upha.LastHistoryDatePerUser, u.CreationDate)) AS ActivityTimeDifference,
    'HighReputationActiveUser' AS QueryBranchType
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserPostHistoryAggregates upha ON u.Id = upha.UserId
LEFT JOIN UserPostTagAggregates upt ON u.Id = upt.UserId
WHERE
    u.Reputation > 500
    AND u.LastAccessDate > NOW() - INTERVAL '1 year' -- Users active in the last year
    AND (
        -- Predicate 1: Users with significant contributions and badges
        (COALESCE(ups.TotalPosts,0) > 100 AND COALESCE(ups.TotalPostScore,0) > 500 AND COALESCE(ubs.TotalBadges,0) > 20)
        OR
        -- Predicate 2: Users focused on specific topics (using string matching) with high upvotes
        (u.DisplayName ILIKE '%data%' OR u.Location ILIKE '%dev%') AND COALESCE(u.UpVotes,0) > 500
    )
    AND u.AboutMe IS NOT NULL -- AboutMe must exist
    AND COALESCE(upha.AvgPostEditCount, 0) > 0 -- Users whose posts have at least one edit history
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    ups.TotalPosts, ups.QuestionCount, ups.AnswerCount, ups.TotalPostScore,
    ups.AvgPostViewCount, ucs.TotalComments, ucs.TotalCommentScore,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TotalBadges,
    upha.AvgPostEditCount, upha.MaxPostCloseCountPerUser, upha.LastHistoryDatePerUser, upha.ControversialPostsCount,
    u.AboutMe, u.Location, u.UpVotes
)
UNION ALL
( -- Start of Query Branch 2: Users with Controversial or Heavily Edited Posts
SELECT
    u.Id AS UserID,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.QuestionCount, 0) AS QuestionCount,
    COALESCE(ups.AnswerCount, 0) AS AnswerCount,
    COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(ups.AvgPostViewCount, 0) AS AvgPostViewCount,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(upha.AvgPostEditCount, 0) AS AvgPostEditCountPerUser,
    COALESCE(upha.MaxPostCloseCountPerUser, 0) AS MaxPostCloseCountPerUser,
    COALESCE(upha.ControversialPostsCount, 0) AS ControversialPostsCount,
    -- Correlated Subquery: average score of user's question posts
    (
        SELECT COALESCE(AVG(p_corr.Score), 0)
        FROM Posts p_corr
        WHERE p_corr.OwnerUserId = u.Id
          AND p_corr.PostTypeId = 1 -- Question posts
          AND p_corr.CreationDate BETWEEN u.CreationDate AND u.LastAccessDate
          AND p_corr.Score IS NOT NULL
    ) AS AvgCorrelatedPostScore,
    -- Window Function: Rank users by their controversial activity
    RANK() OVER (
        ORDER BY
            COALESCE(upha.ControversialPostsCount, 0) DESC,
            COALESCE(upha.MaxPostCloseCountPerUser, 0) DESC,
            COALESCE(upha.AvgPostEditCount, 0) DESC
    ) AS UserRankScore,
    -- Second Window Function: Next user's reputation created on the same day
    COALESCE(LEAD(u.Reputation, 1, 0) OVER (PARTITION BY u.CreationDate::date ORDER BY u.Reputation DESC)::text, 'N/A') AS WindowFuncOutput_Text,
    -- String Aggregate: Low-scoring high-usage tags for the user
    COALESCE(STRING_AGG(upt.TagName, ', ') FILTER (WHERE upt.PostsWithTag > 10 AND upt.AvgScoreForTagPosts < 5), 'No Low-Scoring Tags') AS AggregatedTagsString,
    -- Complex Calculation/Persona Classifier: Categorize users based on post history
    CASE
        WHEN COALESCE(upha.ControversialPostsCount,0) > 10 AND COALESCE(upha.MaxPostCloseCountPerUser,0) > 2 THEN 'Highly Debated'
        WHEN COALESCE(upha.AvgPostEditCount,0) > 5 THEN 'Heavy Editor'
        ELSE 'Regular'
    END AS UserPersonaClassifier,
    -- String Expression: Check if 'moderator' keyword is present in AboutMe
    POSITION(' moderator ' IN LOWER(COALESCE(u.AboutMe, ''))) AS AboutMeStringMetric, -- POSITION returns int (0 if not found)
    -- NULL Logic/Date Arithmetic: Days from user creation to last post history event
    (u.CreationDate - COALESCE(upha.LastHistoryDatePerUser, u.CreationDate)) AS ActivityTimeDifference,
    'ControversialPostUser' AS QueryBranchType
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserPostHistoryAggregates upha ON u.Id = upha.UserId
LEFT JOIN UserPostTagAggregates upt ON u.Id = upt.UserId
WHERE
    u.Reputation > 100
    AND u.LastAccessDate > NOW() - INTERVAL '2 years' -- Wider time window
    AND COALESCE(upha.ControversialPostsCount, 0) > 0 -- Must have at least one controversial post
    AND (
        (COALESCE(upha.MaxPostCloseCountPerUser, 0) > 1 OR COALESCE(upha.ReopenCount, 0) > 0) -- Specific close/reopen activity
        OR
        (COALESCE(upha.AvgPostEditCount, 0) > 10 AND COALESCE(u.UpVotes, 0) < 1000) -- Heavily edited by less popular users
    )
    AND u.EmailHash IS NOT NULL -- EmailHash must exist
    AND u.Location IS NOT NULL -- Location must exist
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    ups.TotalPosts, ups.QuestionCount, ups.AnswerCount, ups.TotalPostScore,
    ups.AvgPostViewCount, ucs.TotalComments, ucs.TotalCommentScore,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TotalBadges,
    upha.AvgPostEditCount, upha.MaxPostCloseCountPerUser, upha.LastHistoryDatePerUser, upha.ControversialPostsCount,
    u.AboutMe, u.Location, u.EmailHash, u.UpVotes
)
ORDER BY Reputation DESC, UserID
LIMIT 2000;
