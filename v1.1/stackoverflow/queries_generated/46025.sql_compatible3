WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
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
        a.ParentId AS QuestionId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) AS UniqueAnswerers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.ParentId
),
TagEngagement AS (
    SELECT 
        tag AS TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        SUM(p.ViewCount) AS TagViews
    FROM Posts p,
    LATERAL (
      SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS tag
    ) s
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY tag
    HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2020-01-01'
    GROUP BY b.UserId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY c.PostId
)
SELECT 
    tqa.DisplayName,
    tqa.QuestionCount,
    ROUND(CAST(tqa.AvgScore AS numeric), 2) AS AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    ROUND(CAST(AVG(am.AnswerCount) AS numeric), 2) AS AvgAnswersPerQuestion,
    ROUND(CAST(AVG(am.AvgAnswerScore) AS numeric), 2) AS AvgAnswerScoreOnQuestions,
    SUM(am.HasAcceptedAnswer) * 1.0 / COUNT(DISTINCT p.Id) AS AcceptanceRate,
    ROUND(CAST(AVG(ca.CommentCount) AS numeric), 2) AS AvgCommentsPerQuestion,
    STRING_AGG(DISTINCT te.TagName, ', ') FILTER (WHERE te.TagName IS NOT NULL) AS TopTags,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountiesStarted,
    ROUND(CAST(AVG(ph.EditCount) AS numeric), 2) AS AvgEditsPerQuestion
FROM TopQuestionAuthors tqa
INNER JOIN Posts p ON p.OwnerUserId = tqa.OwnerUserId AND p.PostTypeId = 1 AND p.CreationDate >= TIMESTAMP '2020-01-01'
LEFT JOIN AnswerMetrics am ON am.QuestionId = p.Id
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tqa.OwnerUserId
LEFT JOIN CommentActivity ca ON ca.PostId = p.Id
LEFT JOIN TagEngagement te ON te.TagName IN (
    SELECT regexp_split_to_table(substring(p2.Tags FROM 2 FOR length(p2.Tags)-2), '><')
    FROM (SELECT p_inner.Id, p_inner.Tags FROM Posts p_inner WHERE p_inner.Id = p.Id) p2
)
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS EditCount
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