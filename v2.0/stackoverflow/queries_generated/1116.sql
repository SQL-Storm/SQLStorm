-- {"query": "1116.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2857} 

WITH UserActivityMetrics AS (
    -- CTE 1: Summarizes user's overall post and comment activity, reputation growth, and time since last access.
    -- This CTE also calculates a 'UserEngagementScore' based on a weighted sum of post scores, comment scores, and up/down votes.
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.UpVotes, 0) AS TotalUpVotes,
        COALESCE(u.DownVotes, 0) AS TotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (3600 * 24 * 365.25) AS AccountAgeYears, -- Age in years
        (
            (COALESCE(u.UpVotes, 0) * 0.5) +
            (COALESCE(SUM(p.Score), 0) * 1.0) +
            (COALESCE(SUM(c.Score), 0) * 0.2) -
            (COALESCE(u.DownVotes, 0) * 0.3) +
            (u.Reputation * 0.01)
        ) AS UserEngagementScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostContentMetrics AS (
    -- CTE 2: Analyzes each post's content and initial engagement/editing activity.
    -- This includes counting specific history events and identifying early attention,
    -- along with a correlated subquery for accepted answer scores.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength, -- Handle NULL Body
        LENGTH(COALESCE(p.Title, '')) AS TitleLength, -- Handle NULL Title
        -- Correlated subquery: Count of initial comments (within 24 hours of creation)
        (
            SELECT COUNT(cm.Id)
            FROM Comments cm
            WHERE cm.PostId = p.Id
              AND cm.CreationDate BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '24 hours'
        ) AS InitialCommentCount,
        -- Count of significant edits (body, tags, or rollbacks of these)
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 6, 8, 9) THEN 1 ELSE 0 END) AS SignificantEditCount,
        -- Time to first body or tag edit (in hours)
        EXTRACT(EPOCH FROM (MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (5, 6))) - p.CreationDate) / 3600 AS TimeToFirstEditHours,
        -- Check if post was closed due to duplication (using CloseReasonTypes IDs)
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('1', '101') THEN 1 ELSE 0 END) AS WasClosedAsDuplicate,
        -- Correlated subquery: Find the maximum score of an accepted answer to this question
        (
            SELECT COALESCE(MAX(ans.Score), 0)
            FROM Posts ans
            WHERE ans.Id = p.AcceptedAnswerId
              AND p.PostTypeId = 1 -- Only applicable for questions
        ) AS AcceptedAnswerMaxScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate,
             p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Tags, p.Body, p.Title, p.AcceptedAnswerId
),
TagPerformance AS (
    -- CTE 3: Analyzes the performance of tags associated with questions.
    -- Uses string_to_array and UNNEST for tags and calculates aggregated metrics per tag.
    SELECT
        UPPER(TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')))) AS TagName,
        COUNT(p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalTagViews,
        MAX(p.CreationDate) AS LatestTagActivity
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 -- Ensure tags are present and valid
    GROUP BY UPPER(TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))))
    HAVING COUNT(p.Id) > 10 -- Only consider tags with a reasonable number of questions
),
UserBadgeSummary AS (
    -- CTE 4: Summarizes badges for each user, differentiating between gold/silver/bronze and tag-based.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ua.UserId,
    ua.UserName,
    ua.Reputation,
    ua.AccountAgeYears,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    ua.AvgCommentScore,
    ua.UserEngagementScore,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    -- Window functions: Rank users by reputation and assign them to reputation tiers
    RANK() OVER (ORDER BY ua.Reputation DESC, ua.UserEngagementScore DESC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY ua.Reputation DESC) AS ReputationTier, -- Divides users into 10 tiers by reputation
    -- Aggregated metrics from PostContentMetrics, focusing on their *impactful* questions
    COUNT(pcm.PostId) AS TotalPostsAnalyzed,
    AVG(pcm.Score) FILTER (WHERE pcm.PostTypeId = 1 AND pcm.AcceptedAnswerMaxScore > 0) AS AvgScoreOnQuestionsWithGoodAcceptedAnswer,
    AVG(pcm.ViewCount) FILTER (WHERE pcm.PostTypeId = 1 AND pcm.InitialCommentCount > 0) AS AvgViewsOnEngagingQuestions,
    SUM(pcm.SignificantEditCount) AS TotalSignificantEditsOnOwnedPosts,
    -- Correlated subquery: Find the most popular tag for the user's questions
    (
        SELECT tp.TagName
        FROM TagPerformance tp
        JOIN Posts p_inner ON p_inner.PostTypeId = 1
                           AND p_inner.OwnerUserId = ua.UserId
                           AND p_inner.Tags LIKE '%' || LOWER(tp.TagName) || '%' -- Case-insensitive tag matching
        GROUP BY tp.TagName, tp.AvgQuestionScore, tp.TotalTagViews
        ORDER BY (tp.AvgQuestionScore * 0.7 + tp.TotalTagViews * 0.3) DESC -- Weighted popularity
        LIMIT 1
    ) AS MostInfluentialTagForUser,
    -- Calculate a "PostFreshnessScore" using LastActivityDate vs. CreationDate
    AVG(
        CASE
            WHEN pcm.LastActivityDate IS NOT NULL AND pcm.CreationDate IS NOT NULL
            THEN 1.0 / (EXTRACT(EPOCH FROM (NOW() - pcm.LastActivityDate)) / 86400.0 + 1) -- Inverse of days since last activity + 1 to avoid division by zero
            ELSE 0.0
        END
    ) AS AvgPostFreshnessScore,
    -- Example of complex calculation involving NULL logic, string operations, and conditional weighting
    SUM(
        COALESCE(pcm.Score, 0) * (1.0 + COALESCE(pcm.InitialCommentCount, 0) / 10.0) -- Score boosted by initial comments
        * CASE
            WHEN pcm.Tags LIKE '%<sql>%' OR pcm.Tags LIKE '%<database>%' THEN 1.5 -- SQL/Database posts get a boost
            WHEN pcm.Tags LIKE '%<javascript>%' THEN 1.2
            WHEN pcm.Tags LIKE '%<python>%' THEN 1.1
            ELSE 1.0
          END
        * NULLIF(SIGN(pcm.ViewCount - 100), -1) -- If ViewCount < 100, factor is 0; otherwise 1. NULLIF(X,-1) returns NULL if X=-1 (meaning ViewCount < 100), effectively making the product 0 when multiplied.
        * CASE WHEN pcm.WasClosedAsDuplicate = 1 THEN 0.5 ELSE 1.0 END -- Closed duplicates penalized
    ) AS WeightedOverallPostImpact
FROM UserActivityMetrics ua
LEFT JOIN PostContentMetrics pcm ON ua.UserId = pcm.OwnerUserId
LEFT JOIN UserBadgeSummary ubs ON ua.UserId = ubs.UserId
WHERE
    ua.Reputation >= 1000 -- Filter for reasonably active/reputable users
    AND ua.TotalQuestions >= 1 -- Must have asked at least one question
    AND ua.TotalAnswers >= 1 -- Must have provided at least one answer
    AND ua.AccountAgeYears >= 0.5 -- Account must be at least 6 months old
    AND ua.DisplayName IS NOT NULL -- Exclude users without a display name
GROUP BY
    ua.UserId, ua.UserName, ua.Reputation, ua.AccountAgeYears, ua.TotalUpVotes, ua.TotalDownVotes,
    ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.AvgPostScore, ua.AvgCommentScore,
    ua.UserEngagementScore, ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
    ubs.TagBasedBadges
HAVING
    COUNT(pcm.PostId) > 5 -- User must have at least 5 posts analyzed for meaningful aggregation
    AND SUM(pcm.SignificantEditCount) > 0 -- User has performed at least one significant edit on their posts
    AND SUM(CASE WHEN pcm.PostTypeId = 1 AND pcm.AcceptedAnswerMaxScore > 0 THEN 1 ELSE 0 END) >= 1 -- At least one question with a good accepted answer
ORDER BY
    ReputationRank ASC, WeightedOverallPostImpact DESC
LIMIT 100;
