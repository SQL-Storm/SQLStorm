WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 200
),
HighlyEngagingQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        -- convert '<t1><t2>' into array by removing leading/trailing angle and splitting on '><'
        regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '>\\<') AS ParsedTags
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND p.ViewCount > 50000
        AND p.Score > 100
        AND p.AnswerCount > 5
        AND EXISTS (
            SELECT 1
            FROM PopularTags pt
            WHERE pt.TagName = ANY(regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '>\\<'))
        )
),
HighlyEngagingQuestionsTags AS (
    SELECT
        heq.QuestionId,
        heq.OwnerUserId,
        heq.CreationDate,
        heq.ViewCount,
        heq.Score,
        tag AS Tag
    FROM HighlyEngagingQuestions heq,
    UNNEST(heq.ParsedTags) AS tag
),
UserQuestionAggregates AS (
    SELECT
        het.OwnerUserId AS UserId,
        COUNT(DISTINCT het.QuestionId) AS TotalHighQualityQuestions,
        SUM(het.ViewCount) AS SumQuestionViews,
        AVG(het.Score) AS AverageQuestionScore,
        ARRAY_AGG(DISTINCT het.Tag) AS AllUserTags,
        MAX(het.CreationDate) AS LatestQuestionDate
    FROM HighlyEngagingQuestionsTags het
    GROUP BY het.OwnerUserId
),
UserAcceptedAnswerAggregates AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(DISTINCT a.Id) AS TotalAcceptedAnswers,
        AVG(a.Score) AS AvgScoreAcceptedAnswers,
        MAX(a.CreationDate) AS LatestAcceptedAnswerDate
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE
        a.PostTypeId = 2
        AND q.AcceptedAnswerId = a.Id
        AND a.Score > 50
    GROUP BY a.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserPostHistoryEdits AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.Id) AS TotalSignificantEdits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.UserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.Score >= 5
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
    COALESCE(array_length(uqa.AllUserTags, 1), 0) AS DistinctTagsContributed,
    COALESCE(uaa.TotalAcceptedAnswers, 0) AS TotalAcceptedAnswers,
    COALESCE(uaa.AvgScoreAcceptedAnswers, 0.0) AS AvgScoreAcceptedAnswers,
    COALESCE(ubc.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(ubc.SilverBadgeCount, 0) AS SilverBadgeCount,
    COALESCE(upe.TotalSignificantEdits, 0) AS TotalSignificantEdits,
    COALESCE(uca.TotalComments, 0) AS TotalHighScoreComments,
    COALESCE(uca.AvgCommentScore, 0.0) AS AvgHighScoreCommentScore,
    (
        u.Reputation * 0.3 +
        COALESCE(uqa.SumQuestionViews / 1000.0, 0) * 0.1 +
        COALESCE(uqa.AverageQuestionScore, 0) * 0.05 +
        COALESCE(array_length(uqa.AllUserTags, 1), 0) * 0.02 +
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
FROM Users u
LEFT JOIN UserQuestionAggregates uqa ON u.Id = uqa.UserId
LEFT JOIN UserAcceptedAnswerAggregates uaa ON u.Id = uaa.UserId
LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN UserPostHistoryEdits upe ON u.Id = upe.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
WHERE
    u.Reputation > 50000
    AND u.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    AND (uqa.TotalHighQualityQuestions IS NOT NULL OR uaa.TotalAcceptedAnswers IS NOT NULL)
ORDER BY
    OverallRank ASC,
    CompositeEngagementScore DESC
LIMIT 500;