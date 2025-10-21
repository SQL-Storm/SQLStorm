-- {"query": "49068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2153} 
WITH RelevantTags AS (
    -- Define a set of highly relevant technical tags to focus the analysis.
    -- This simulates a dynamic selection based on common interests.
    SELECT TagName FROM Tags WHERE TagName IN ('sql', 'postgresql', 'performance', 'database', 'indexing', 'query-optimization', 'data-modeling', 'bigquery', 'nosql', 'json')
),
PopularQuestionPosts AS (
    -- Identify questions that are highly engaged: high views, good scores, multiple answers, and favorited,
    -- and are associated with our relevant tags.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS QuestionOwnerId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
      AND p.ViewCount > 50000 -- Significant view threshold
      AND p.Score > 100 -- High score threshold
      AND p.AnswerCount > 10 -- Active discussion
      AND p.FavoriteCount > 50 -- Many users bookmarked
      AND EXISTS (
          -- Efficiently check for tag relevance using string_to_array and unnest (PostgreSQL specific)
          SELECT 1
          FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS post_tag
          INNER JOIN RelevantTags rt ON post_tag = rt.TagName
      )
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years') -- Focus on recent history
),
UserQuestionStats AS (
    -- Aggregate statistics for users who own these popular questions.
    -- Includes total contributions and average engagement metrics for their questions.
    SELECT
        pqp.QuestionOwnerId AS UserId,
        COUNT(pqp.PostId) AS TotalPopularQuestions,
        SUM(pqp.QuestionScore) AS TotalQuestionScore,
        AVG(CAST(pqp.ViewCount AS NUMERIC)) AS AvgQuestionViewCount,
        AVG(CAST(pqp.AnswerCount AS NUMERIC)) AS AvgQuestionAnswerCount,
        SUM(pqp.FavoriteCount) AS TotalQuestionFavorites
    FROM PopularQuestionPosts pqp
    GROUP BY pqp.QuestionOwnerId
    HAVING COUNT(pqp.PostId) >= 5 -- Users with at least 5 popular questions
),
UserAnswerContributions AS (
    -- Analyze the quality and quantity of answers provided by these users,
    -- distinguishing between accepted answers and others.
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(CAST(a.Score AS NUMERIC)) AS AvgAnswerScore,
        COUNT(DISTINCT a.ParentId) AS AnsweredUniqueQuestions,
        SUM(CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        SUM(CASE WHEN a.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') THEN 1 ELSE 0 END) AS RecentAnswersCount
    FROM Posts a
    WHERE a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
      AND a.OwnerUserId IN (SELECT UserId FROM UserQuestionStats)
      AND a.Score > 0 -- Only consider positively scored answers
    GROUP BY a.OwnerUserId
),
UserPostEditActivity AS (
    -- Track granular editing activity, distinguishing between initial content creation and subsequent edits.
    -- Focus on the textual changes and tag modifications.
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.PostId) AS UniquePostsWithHistory,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%' AND Name NOT LIKE '%Rollback%') THEN 1 ELSE 0 END) AS ContentEditsCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Initial%') THEN 1 ELSE 0 END) AS InitialContentCreationsCount,
        -- Calculate average days between post creation and first edit by the same user
        AVG(CASE
            WHEN ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%' AND Name NOT LIKE '%Rollback%') THEN
                EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) / (60 * 60 * 24)
            ELSE NULL
        END) AS AvgDaysToFirstEdit,
        SUM(CASE WHEN ph.Text IS NOT NULL AND LENGTH(ph.Text) > 100 THEN 1 ELSE 0 END) AS SignificantEdits
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id AND ph.UserId = p.OwnerUserId
    WHERE ph.UserId IN (SELECT UserId FROM UserQuestionStats)
      AND ph.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years')
    GROUP BY ph.UserId
),
UserBadgeSummary AS (
    -- Summarize badge achievements, categorizing by class (Gold, Silver, Bronze)
    -- and determining the recency of badge acquisitions.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        SUM(CASE WHEN b.Date >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') THEN 1 ELSE 0 END) AS RecentBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT UserId FROM UserQuestionStats)
    GROUP BY b.UserId
)
-- Final aggregation and ranking of influential users based on a composite influence score.
-- The score weights various contributions, reputation, and activity levels.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    uqs.TotalPopularQuestions,
    uqs.TotalQuestionScore,
    uqs.AvgQuestionViewCount,
    uac.TotalAnswers,
    uac.TotalAnswerScore,
    uac.AvgAnswerScore,
    uac.AcceptedAnswersCount,
    uac.RecentAnswersCount,
    uea.TotalHistoryEvents AS TotalPostActivity,
    uea.ContentEditsCount,
    uea.InitialContentCreationsCount,
    uea.SignificantEdits,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.LatestBadgeDate,
    ubs.RecentBadges,
    -- Calculate a comprehensive InfluenceScore with various weighted factors
    (u.Reputation * 0.05) +
    (uqs.TotalPopularQuestions * 10) +
    (uqs.TotalQuestionScore * 0.02) +
    (uqs.TotalQuestionFavorites * 0.5) +
    (uac.TotalAnswers * 3) +
    (uac.TotalAnswerScore * 0.01) +
    (uac.AcceptedAnswersCount * 7) +
    (uea.ContentEditsCount * 1.5) +
    (uea.SignificantEdits * 2) +
    (ubs.GoldBadges * 100) +
    (ubs.SilverBadges * 20) +
    (ubs.RecentBadges * 5) AS InfluenceScore,
    -- Rank users based on their calculated InfluenceScore
    RANK() OVER (ORDER BY (
        (u.Reputation * 0.05) +
        (uqs.TotalPopularQuestions * 10) +
        (uqs.TotalQuestionScore * 0.02) +
        (uqs.TotalQuestionFavorites * 0.5) +
        (uac.TotalAnswers * 3) +
        (uac.TotalAnswerScore * 0.01) +
        (uac.AcceptedAnswersCount * 7) +
        (uea.ContentEditsCount * 1.5) +
        (uea.SignificantEdits * 2) +
        (ubs.GoldBadges * 100) +
        (ubs.SilverBadges * 20) +
        (ubs.RecentBadges * 5)
    ) DESC) AS InfluenceRank
FROM Users u
INNER JOIN UserQuestionStats uqs ON u.Id = uqs.UserId
LEFT JOIN UserAnswerContributions uac ON u.Id = uac.UserId
LEFT JOIN UserPostEditActivity uea ON u.Id = uea.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
WHERE u.Reputation > 25000 -- Filter for highly reputed users
  AND u.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months') -- Recently active users
ORDER BY InfluenceScore DESC, u.CreationDate ASC
LIMIT 200;