-- {"query": "46025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1549}

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score > 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as QuestionId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as MaxAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) as UniqueAnswerers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) as HasAcceptedAnswer
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.ParentId
),
TagEngagement AS (
    SELECT 
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgTagScore,
        SUM(p.ViewCount) as TagViews
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY TagName
    HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        COUNT(DISTINCT b.Name) as UniqueBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2020-01-01'
    GROUP BY b.UserId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT c.UserId) as UniqueCommenters,
        AVG(c.Score) as AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY c.PostId
)
SELECT 
    tqa.DisplayName,
    tqa.QuestionCount,
    ROUND(tqa.AvgScore::numeric, 2) as AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ubs.GoldBadges, 0) as GoldBadges,
    COALESCE(ubs.SilverBadges, 0) as SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) as BronzeBadges,
    ROUND(AVG(am.AnswerCount)::numeric, 2) as AvgAnswersPerQuestion,
    ROUND(AVG(am.AvgAnswerScore)::numeric, 2) as AvgAnswerScoreOnQuestions,
    SUM(am.HasAcceptedAnswer)::float / COUNT(DISTINCT p.Id) as AcceptanceRate,
    ROUND(AVG(ca.CommentCount)::numeric, 2) as AvgCommentsPerQuestion,
    STRING_AGG(DISTINCT te.TagName, ', ' ORDER BY te.PostCount DESC) FILTER (WHERE te.PostCount IS NOT NULL) as TopTags,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as TotalUpvotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 8) as BountiesStarted,
    ROUND(AVG(ph.EditCount)::numeric, 2) as AvgEditsPerQuestion
FROM TopQuestionAuthors tqa
INNER JOIN Posts p ON p.OwnerUserId = tqa.OwnerUserId AND p.PostTypeId = 1 AND p.CreationDate >= TIMESTAMP '2020-01-01'
LEFT JOIN AnswerMetrics am ON am.QuestionId = p.Id
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tqa.OwnerUserId
LEFT JOIN CommentActivity ca ON ca.PostId = p.Id
LEFT JOIN TagEngagement te ON te.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
) ph ON ph.PostId = p.Id
GROUP BY 
    tqa.DisplayName, 
    tqa.QuestionCount, 
    tqa.AvgScore, 
    tqa.TotalViews,
    tqa.OwnerUserId,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges
HAVING COUNT(DISTINCT p.Id) >= 10
ORDER BY tqa.TotalViews DESC, tqa.AvgScore DESC
LIMIT 100;
