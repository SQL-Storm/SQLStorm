-- {"query": "1997.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3605} 

WITH UserEngagement AS (
    -- CTE 1: Aggregate user-level activity from Posts and Comments, calculate an initial engagement score
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.AboutMe,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) AS AvgQuestionScore,
        COALESCE(MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS MaxAnswerScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN c.UserId = u.Id THEN c.Score ELSE 0 END) AS TotalCommentScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MIN(p.CreationDate) AS FirstPostDate,
        -- Complex calculation: "Engagement Score" combining multiple factors
        (u.Reputation * 0.1) +
        (COUNT(DISTINCT p.Id) * 0.5) +
        (COUNT(DISTINCT c.Id) * 0.2) +
        COALESCE(SUM(p.Score), 0) * 0.05 +
        COALESCE(SUM(p.ViewCount), 0) * 0.001 +
        (CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 10 ELSE 0 END) -- Bonus for detailed profile
        AS EngagementScore,
        -- Correlated subquery 1: Check if user has at least one accepted answer on one of their own questions
        EXISTS (
            SELECT 1
            FROM Posts own_q
            INNER JOIN Posts accepted_a ON own_q.AcceptedAnswerId = accepted_a.Id
            WHERE own_q.PostTypeId = 1
              AND own_q.OwnerUserId = u.Id
              AND accepted_a.OwnerUserId = u.Id
            LIMIT 1
        ) AS HasSelfAcceptedAnswer
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.AboutMe
),
PostHistoryMetrics AS (
    -- CTE 2: Analyze post history for edits, closures, and distinct editors, including time differences
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        -- Identify if the post has ever been officially closed via history
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS HasBeenClosedViaHistory,
        -- Correlated subquery 2: Find the latest editor's display name, handling NULLs
        COALESCE(
            (SELECT COALESCE(ph_latest.UserDisplayName, u_latest.DisplayName, 'Community')
             FROM PostHistory ph_latest
             LEFT JOIN Users u_latest ON ph_latest.UserId = u_latest.Id
             WHERE ph_latest.PostId = ph.PostId
             ORDER BY ph_latest.CreationDate DESC
             LIMIT 1),
            'Original Creator'
        ) AS LatestEditorDisplayName,
        -- Window function: Calculate the time difference (in minutes) between the first and last edit for a post
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))) / 60.0 AS TotalEditTimeMinutes
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
),
TagDominance AS (
    -- CTE 3: Identify dominant tags for users based on their questions, showing count
    SELECT
        UserId,
        STRING_AGG(TagName || ' (' || PostCount || ')', '; ') AS TopTagsSummary
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName,
            COUNT(DISTINCT p.Id) AS PostCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(DISTINCT p.Id) DESC, TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')))) AS rn
        FROM
            Posts p
        WHERE
            p.PostTypeId = 1 -- Only consider questions for tag dominance
            AND p.Tags IS NOT NULL
            AND p.OwnerUserId IS NOT NULL
        GROUP BY
            p.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')))
    ) AS TaggedPosts
    WHERE rn <= 3 -- Get top 3 tags
    GROUP BY UserId
),
VoteAnalysis AS (
    -- CTE 4: Analyze user voting patterns (as voters and recipients)
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS PostsFavorited
    FROM
        Users u
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id
),
PostDetailsExtended AS (
    -- CTE 5: Combine relevant post-level details for joining, including derived quality scores
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS PostOwnerId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.ClosedDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        phm.HasBeenClosedViaHistory,
        phm.EditCount,
        phm.LatestEditorDisplayName,
        phm.TotalEditTimeMinutes,
        -- Complicated expression: derived "PostQualityScore"
        (p.Score * 5.0) +
        (COALESCE(p.ViewCount, 0) * 0.1) +
        (COALESCE(p.AnswerCount, 0) * 2.0) +
        (COALESCE(p.CommentCount, 0) * 1.0) +
        (COALESCE(p.FavoriteCount, 0) * 10.0) -
        (CASE WHEN p.ClosedDate IS NOT NULL THEN 100 ELSE 0 END) - -- Penalty for closed posts
        (COALESCE(phm.EditCount, 0) * 0.5) -- Slight penalty for excessive edits
        AS PostQualityScore,
        -- String expression: Extract first tag if available, using NULL logic
        COALESCE(SUBSTRING(p.Tags FROM POSITION('<' IN p.Tags) + 1 FOR POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1), 'no-tag') AS FirstTag,
        -- NULL logic: Is Post an unanswered question?
        (p.PostTypeId = 1 AND p.AnswerCount IS NULL AND p.AcceptedAnswerId IS NULL) AS IsUnansweredQuestion
    FROM
        Posts p
    LEFT JOIN
        PostHistoryMetrics phm ON p.Id = phm.PostId
),
QuestionCentricUsers AS (
    -- Set operator part 1: Users primarily focused on questions (more questions than answers)
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.EngagementScore,
        td.TopTagsSummary,
        va.UpvotesGiven,
        va.DownvotesGiven,
        va.PostsFavorited,
        'Question_Focused' AS UserCategory,
        AVG(pde.PostQualityScore) AS AvgPostQualityForCategory,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        UserEngagement ue
    LEFT JOIN
        TagDominance td ON ue.UserId = td.UserId
    LEFT JOIN
        VoteAnalysis va ON ue.UserId = va.UserId
    LEFT JOIN
        PostDetailsExtended pde ON ue.UserId = pde.PostOwnerId AND pde.PostTypeId = 1
    LEFT JOIN
        Badges b ON ue.UserId = b.UserId
    WHERE
        ue.TotalQuestions > ue.TotalAnswers
        AND ue.TotalQuestions > 0
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalQuestions, ue.TotalAnswers, ue.EngagementScore,
        td.TopTagsSummary, va.UpvotesGiven, va.DownvotesGiven, va.PostsFavorited
),
AnswerCentricUsers AS (
    -- Set operator part 2: Users primarily focused on answers (answers equal or exceed questions)
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.EngagementScore,
        td.TopTagsSummary,
        va.UpvotesGiven,
        va.DownvotesGiven,
        va.PostsFavorited,
        'Answer_Focused' AS UserCategory,
        AVG(pde.PostQualityScore) AS AvgPostQualityForCategory,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        UserEngagement ue
    LEFT JOIN
        TagDominance td ON ue.UserId = td.UserId
    LEFT JOIN
        VoteAnalysis va ON ue.UserId = va.UserId
    LEFT JOIN
        PostDetailsExtended pde ON ue.UserId = pde.PostOwnerId AND pde.PostTypeId = 2
    LEFT JOIN
        Badges b ON ue.UserId = b.UserId
    WHERE
        ue.TotalAnswers >= ue.TotalQuestions
        AND ue.TotalAnswers > 0
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalQuestions, ue.TotalAnswers, ue.EngagementScore,
        td.TopTagsSummary, va.UpvotesGiven, va.DownvotesGiven, va.PostsFavorited
)
-- Main query: Combine user categories and apply final aggregations and window functions
SELECT
    FinalUsers.UserId,
    FinalUsers.DisplayName,
    FinalUsers.Reputation,
    FinalUsers.UserCategory,
    FinalUsers.TotalQuestions,
    FinalUsers.TotalAnswers,
    FinalUsers.EngagementScore,
    FinalUsers.TopTagsSummary,
    FinalUsers.UpvotesGiven,
    FinalUsers.DownvotesGiven,
    FinalUsers.PostsFavorited,
    FinalUsers.TotalBadges,
    COALESCE(FinalUsers.AvgPostQualityForCategory, 0) AS AvgPostQualityForCategory,
    -- Window function: Rank users by Engagement Score within their category
    RANK() OVER (PARTITION BY FinalUsers.UserCategory ORDER BY FinalUsers.EngagementScore DESC, FinalUsers.Reputation DESC) AS EngagementRankByCategory,
    -- Window function: Distribute users into 10 buckets based on Reputation globally
    NTILE(10) OVER (ORDER BY FinalUsers.Reputation DESC) AS ReputationTier,
    -- Complicated predicate: Users identified as potential "Rising Stars"
    (ue.EngagementScore > (SELECT AVG(EngagementScore) * 1.2 FROM UserEngagement WHERE TotalQuestions > 0 OR TotalAnswers > 0)
     AND FinalUsers.TotalBadges < 5
     AND ue.HasSelfAcceptedAnswer IS TRUE
     AND ue.LastAccessDate >= (NOW() - INTERVAL '6 months')) AS IsRisingStarWithSelfSolve,
    -- String expression: Cleaned Location (if exists and not too generic, otherwise 'Unknown')
    COALESCE(LOWER(TRIM(SUBSTRING(u.Location FROM 1 FOR 50))), 'Unknown') AS CleanedLocation,
    -- Correlated Subquery 3: Count of questions that have been linked by more than 2 other posts
    (SELECT COUNT(DISTINCT pl.PostId)
     FROM PostLinks pl
     WHERE pl.RelatedPostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = FinalUsers.UserId AND p.PostTypeId = 1)
       AND pl.LinkTypeId = 1 -- Linked posts
     HAVING COUNT(DISTINCT pl.PostId) > 2
    ) AS LinkedQuestionCountThreshold,
    -- Another correlated subquery in SELECT, finding the average score of all answers to questions posted by this user
    (SELECT COALESCE(AVG(ans.Score), 0)
     FROM Posts q
     INNER JOIN Posts ans ON q.Id = ans.ParentId
     WHERE q.OwnerUserId = FinalUsers.UserId
       AND q.PostTypeId = 1
       AND ans.PostTypeId = 2
    ) AS AvgAnswerScoreToOwnQuestions,
    -- Case expression for User Website Status
    CASE
        WHEN ue.WebsiteUrl IS NULL OR ue.WebsiteUrl = '' THEN 'No Website'
        WHEN ue.WebsiteUrl LIKE '%linkedin.com%' THEN 'Professional Profile'
        WHEN ue.WebsiteUrl LIKE '%github.com%' THEN 'Developer Portfolio'
        ELSE 'Other Website'
    END AS WebsiteStatus
FROM
    (SELECT * FROM QuestionCentricUsers UNION ALL SELECT * FROM AnswerCentricUsers) AS FinalUsers
INNER JOIN
    UserEngagement ue ON FinalUsers.UserId = ue.UserId -- Join back for additional details from UE like HasSelfAcceptedAnswer and LastAccessDate
LEFT JOIN
    Users u ON FinalUsers.UserId = u.Id -- Join back for User table specific columns like Location
WHERE
    FinalUsers.Reputation > 100 -- Filter for more established users
    AND (FinalUsers.TotalQuestions + FinalUsers.TotalAnswers) > 5 -- At least some activity
    AND (u.LastAccessDate >= (NOW() - INTERVAL '1 year') OR u.LastAccessDate IS NULL) -- Active in last year or never accessed (NULL logic)
    AND (FinalUsers.UserCategory = 'Question_Focused' OR FinalUsers.AvgPostQualityForCategory > (SELECT AVG(PostQualityScore) FROM PostDetailsExtended WHERE PostTypeId = 2) * 0.8) -- Complex filter
ORDER BY
    EngagementRankByCategory ASC, FinalUsers.Reputation DESC, FinalUsers.UserId
LIMIT 5000;
