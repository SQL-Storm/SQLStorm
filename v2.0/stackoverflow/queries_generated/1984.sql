-- {"query": "1984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2313} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL), 0) AS AverageMeaningfulPostScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        DATE_PART('day', NOW() - MAX(p.LastActivityDate)) AS DaysSinceLastPostActivity
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' -- Filter for users created after a certain date
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.UpVotes, u.DownVotes
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        p.CreationDate AS PostCreationDate
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL
      AND p.PostTypeId = 1 -- Only analyze tags for questions
),
UserTagDominance AS (
    SELECT
        pta.OwnerUserId AS UserId,
        pta.TagName,
        COUNT(*) AS TagCount,
        RANK() OVER (PARTITION BY pta.OwnerUserId ORDER BY COUNT(*) DESC, pta.TagName) AS TagRankByUser
    FROM PostTagAnalysis AS pta
    GROUP BY pta.OwnerUserId, pta.TagName
),
UserContributionRank AS (
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.TotalQuestions,
        ues.TotalAnswers,
        ues.TotalPostScore,
        ues.AverageMeaningfulPostScore,
        ues.TotalBadges,
        ues.DaysSinceLastPostActivity,
        -- Window function: Rank users by a weighted score of reputation, post score, and badges
        DENSE_RANK() OVER (ORDER BY ues.Reputation DESC, ues.TotalPostScore DESC, ues.TotalBadges DESC) AS OverallUserRank,
        -- Window function: Calculate average answer score for users with answers (if any)
        COALESCE(AVG(p_ans.Score) OVER (PARTITION BY ues.UserId), 0) AS AvgAnswerScoreForUser
    FROM UserEngagementSummary AS ues
    LEFT JOIN Posts AS p_ans ON ues.UserId = p_ans.OwnerUserId AND p_ans.PostTypeId = 2
),
ModeratorActivity AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalModerationActions,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14) THEN 1 ELSE NULL END) AS DestructiveActions, -- Close, Delete, Lock
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15) THEN 1 ELSE NULL END) AS ConstructiveActions, -- Reopen, Undelete, Unlock
        MAX(ph.CreationDate) AS LastModerationDate
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Common moderator actions
    GROUP BY ph.UserId
),
TopQuestionVotes AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpvoteCount, -- UpMod
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownvoteCount, -- DownMod
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE NULL END) AS FavoriteCount, -- Favorite
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS RankWithinUserQuestions
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
    HAVING COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) > 5 -- At least 5 upvotes
)
SELECT
    ucr.UserId,
    LOWER(ucr.DisplayName) AS UserHandle,
    ucr.Reputation,
    ucr.OverallUserRank,
    ucr.TotalQuestions,
    ucr.TotalAnswers,
    ucr.AverageMeaningfulPostScore,
    COALESCE(MOD(ucr.TotalQuestions + ucr.TotalAnswers, 7), 0) AS ActivityCycleMod, -- A fancy calculation
    uta.TagName AS MostDominantTag,
    uta.TagCount AS DominantTagUsageCount,
    -- Complicated predicate/expression using CASE and NULLIF
    CASE
        WHEN ucr.Reputation >= 5000 AND ucr.TotalQuestions >= 50 THEN 'High-Volume Expert'
        WHEN ucr.Reputation >= 2000 AND ucr.TotalAnswers >= 100 THEN 'Prodigious Answerer'
        WHEN ucr.Reputation < 500 AND ucr.DaysSinceLastPostActivity > 90 THEN 'Dormant Contributor'
        WHEN ucr.TotalBadges >= 10 AND ucr.AverageMeaningfulPostScore > 5 THEN 'Recognized Engager'
        ELSE 'Active Participant'
    END AS User_Tier,
    -- Correlated subquery: check if user has a question with significantly higher score than their own average post score
    EXISTS (
        SELECT 1
        FROM Posts AS p_inner
        WHERE p_inner.OwnerUserId = ucr.UserId
          AND p_inner.PostTypeId = 1
          AND p_inner.Score IS NOT NULL
          AND p_inner.Score > (ucr.AverageMeaningfulPostScore * 1.5) -- 50% higher than average
          AND COALESCE(p_inner.ViewCount, 0) > 1000 -- and also popular
    ) AS HasBreakoutQuestion,
    COALESCE(ma.TotalModerationActions, 0) AS ModeratorActionCount,
    -- LEFT JOIN with TopQuestionVotes to get info about their best question, if any
    tqv.QuestionScore AS BestQuestionScore,
    tqv.UpvoteCount AS BestQuestionUpvotes,
    tqv.FavoriteCount AS BestQuestionFavorites,
    -- String expression from Location, handling NULLs
    COALESCE(SUBSTRING(u.Location, 1, 20), 'Unknown Location') AS ShortLocation,
    -- Another complex calculation with NULL handling and division by zero
    CAST(ucr.UpVotes AS NUMERIC) / NULLIF(ucr.DownVotes + COALESCE(ma.DestructiveActions, 0), 0) AS UpvoteToDownvoteRatioAdjusted
FROM UserContributionRank AS ucr
JOIN Users AS u ON ucr.UserId = u.Id
LEFT JOIN UserTagDominance AS uta ON ucr.UserId = uta.UserId AND uta.TagRankByUser = 1 -- Get the top tag for each user
LEFT JOIN ModeratorActivity AS ma ON ucr.UserId = ma.UserId
LEFT JOIN TopQuestionVotes AS tqv ON ucr.UserId = tqv.OwnerUserId AND tqv.RankWithinUserQuestions = 1 -- Get their top question
WHERE ucr.Reputation > 100
  AND ucr.TotalPosts > 0
  AND (ucr.DaysSinceLastPostActivity <= 180 OR ucr.TotalBadges >= 50) -- Active within 6 months OR very experienced
  -- Additional filtering with string matching and NULL logic
  AND (u.Location LIKE '%United States%' OR u.Location LIKE '%Canada%' OR u.Location IS NULL)
  AND u.DisplayName IS NOT NULL
  -- Correlated subquery to check if user has made a comment on one of their own posts that was closed with a specific reason
  AND EXISTS (
      SELECT 1
      FROM Comments AS c_inner
      JOIN Posts AS p_closed ON c_inner.PostId = p_closed.Id
      JOIN PostHistory AS ph_closed ON p_closed.Id = ph_closed.PostId AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
      WHERE c_inner.UserId = ucr.UserId
        AND p_closed.OwnerUserId = ucr.UserId
        AND p_closed.ClosedDate IS NOT NULL
        AND c_inner.Score > 0 -- Positive score comment
        AND ph_closed.Comment IN ('101', '102') -- Closed as Duplicate or Off-topic (based on CloseReasonTypes Id)
  )
ORDER BY ucr.OverallUserRank ASC, ucr.Reputation DESC, ucr.DisplayName
LIMIT 1000;
