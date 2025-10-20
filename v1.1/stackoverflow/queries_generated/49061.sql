-- {"query": "49061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1766} 

WITH PopularTags AS (
    -- Identify the top 200 most frequently used tags, which will be used to filter relevant posts.
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 200
),
HighlyEngagingQuestions AS (
    -- Filter for questions that are highly viewed, well-scored, and belong to one of the popular tags.
    -- This step involves string manipulation for tag parsing and checking against a set of popular tags.
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS ParsedTags
    FROM Posts AS p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.ViewCount > 50000 -- Significant view count
        AND p.Score > 100 -- High score indicates quality
        AND p.AnswerCount > 5 -- Questions with multiple answers
        AND EXISTS (
            SELECT 1
            FROM PopularTags pt
            WHERE pt.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
        )
),
UserQuestionAggregates AS (
    -- Aggregate engagement metrics for users based on their highly engaging questions.
    -- This includes total questions, views, scores, and a unique list of all tags they've used.
    SELECT
        heq.OwnerUserId AS UserId,
        COUNT(DISTINCT heq.QuestionId) AS TotalHighQualityQuestions,
        SUM(heq.ViewCount) AS SumQuestionViews,
        AVG(heq.Score) AS AverageQuestionScore,
        ARRAY_AGG(DISTINCT UNNEST(heq.ParsedTags)) AS AllUserTags,
        MAX(heq.CreationDate) AS LatestQuestionDate
    FROM HighlyEngagingQuestions heq
    GROUP BY heq.OwnerUserId
),
UserAcceptedAnswerAggregates AS (
    -- Calculate metrics for accepted answers provided by users.
    -- Focus on answers that received a high score themselves.
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(DISTINCT a.Id) AS TotalAcceptedAnswers,
        AVG(a.Score) AS AvgScoreAcceptedAnswers,
        MAX(a.CreationDate) AS LatestAcceptedAnswerDate
    FROM Posts AS a
    JOIN Posts AS q ON a.ParentId = q.Id
    WHERE
        a.PostTypeId = 2 -- Is an answer
        AND q.AcceptedAnswerId = a.Id -- This answer was accepted
        AND a.Score > 50 -- The accepted answer itself is highly scored
    GROUP BY a.OwnerUserId
),
UserBadgeCounts AS (
    -- Count gold and silver badges for users.
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount
    FROM Badges AS b
    GROUP BY b.UserId
),
UserPostHistoryEdits AS (
    -- Count significant edits (title, body, tags, rollbacks) made by users on their posts.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.Id) AS TotalSignificantEdits
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit Title, Body, Tags, or corresponding Rollbacks
    GROUP BY ph.UserId
),
UserCommentActivity AS (
    -- Aggregate comment activity, focusing on highly scored comments.
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments AS c
    WHERE c.Score >= 5 -- Only consider highly scored comments
    GROUP BY c.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(uqa.TotalHighQualityQuestions, 0) AS TotalHighQualityQuestions,
    COALESCE(uqa.SumQuestionViews, 0) AS SumQuestionViews,
    COALESCE(uqa.AverageQuestionScore, 0.0) AS AverageQuestionScore,
    COALESCE(CARDINALITY(uqa.AllUserTags), 0) AS DistinctTagsContributed,
    COALESCE(uaa.TotalAcceptedAnswers, 0) AS TotalAcceptedAnswers,
    COALESCE(uaa.AvgScoreAcceptedAnswers, 0.0) AS AvgScoreAcceptedAnswers,
    COALESCE(ubc.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(ubc.SilverBadgeCount, 0) AS SilverBadgeCount,
    COALESCE(upe.TotalSignificantEdits, 0) AS TotalSignificantEdits,
    COALESCE(uca.TotalComments, 0) AS TotalHighScoreComments,
    COALESCE(uca.AvgCommentScore, 0.0) AS AvgHighScoreCommentScore,
    -- Calculate a composite score based on various engagement metrics for ranking
    (
        u.Reputation * 0.3 +
        COALESCE(uqa.SumQuestionViews / 1000.0, 0) * 0.1 +
        COALESCE(uqa.AverageQuestionScore, 0) * 0.05 +
        COALESCE(CARDINALITY(uqa.AllUserTags), 0) * 0.02 +
        COALESCE(uaa.TotalAcceptedAnswers, 0) * 0.15 +
        COALESCE(uaa.AvgScoreAcceptedAnswers, 0) * 0.1 +
        COALESCE(ubc.GoldBadgeCount, 0) * 20 +
        COALESCE(ubc.SilverBadgeCount, 0) * 5 +
        COALESCE(upe.TotalSignificantEdits, 0) * 0.01 +
        COALESCE(uca.TotalComments, 0) * 0.005
    ) AS CompositeEngagementScore,
    RANK() OVER (
        ORDER BY
            u.Reputation DESC,
            COALESCE(uqa.TotalHighQualityQuestions, 0) DESC,
            COALESCE(uaa.TotalAcceptedAnswers, 0) DESC,
            COALESCE(ubc.GoldBadgeCount, 0) DESC,
            u.LastAccessDate DESC
    ) AS OverallRank
FROM Users AS u
LEFT JOIN UserQuestionAggregates AS uqa ON u.Id = uqa.UserId
LEFT JOIN UserAcceptedAnswerAggregates AS uaa ON u.Id = uaa.UserId
LEFT JOIN UserBadgeCounts AS ubc ON u.Id = ubc.UserId
LEFT JOIN UserPostHistoryEdits AS upe ON u.Id = upe.UserId
LEFT JOIN UserCommentActivity AS uca ON u.Id = uca.UserId
WHERE
    u.Reputation > 50000 -- Focus on highly reputable users
    AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year' -- Users active in the last year
    AND (uqa.TotalHighQualityQuestions IS NOT NULL OR uaa.TotalAcceptedAnswers IS NOT NULL) -- Must have contributed either high-quality questions or accepted answers
ORDER BY
    OverallRank ASC,
    CompositeEngagementScore DESC
LIMIT 500;
