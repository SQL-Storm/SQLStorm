WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererUserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT v.Id) AS VotesCast,
        COUNT(DISTINCT c.Id) AS CommentsPosted
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= TIMESTAMP '2015-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(p.AnswerCount) AS AvgAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 100
),
TopTagsPerUser AS (
    SELECT
        p.OwnerUserId,
        tp.TagName,
        tp.QuestionCount,
        tp.AvgQuestionScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY tp.QuestionCount DESC, tp.TagName) AS rn
    FROM Posts p
    JOIN TagPerformance tp ON p.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
    GROUP BY p.OwnerUserId, tp.TagName, tp.QuestionCount, tp.AvgQuestionScore
)
SELECT 
    tqa.OwnerUserId,
    ue.DisplayName,
    ue.Reputation,
    tqa.QuestionCount,
    tqa.AvgScore AS AvgQuestionScore,
    tqa.TotalViews,
    ue.BadgeCount,
    ue.GoldBadges,
    COUNT(DISTINCT am.AnswerId) AS AnswersReceived,
    AVG(am.AnswerScore) AS AvgAnswerScore,
    COUNT(DISTINCT CASE WHEN am.AnswerRank = 1 THEN am.AnswerId END) AS TopAnswersReceived,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkedPosts,
    STRING_AGG(tt.TagName, ', ' ORDER BY tt.QuestionCount DESC) FILTER (WHERE tt.TagName IS NOT NULL) AS TopTags,
    MAX(tt.AvgQuestionScore) AS BestTagAvgScore,
    ue.VotesCast,
    ue.CommentsPosted,
    EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400.0 AS DaysActive
FROM TopQuestionAuthors tqa
JOIN UserEngagement ue ON tqa.OwnerUserId = ue.UserId
JOIN Posts p ON p.OwnerUserId = tqa.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN AnswerMetrics am ON p.Id = am.QuestionId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN TopTagsPerUser tt ON tqa.OwnerUserId = tt.OwnerUserId AND tt.rn <= 5
WHERE ue.Reputation > 1000
GROUP BY 
    tqa.OwnerUserId,
    ue.DisplayName,
    ue.Reputation,
    tqa.QuestionCount,
    tqa.AvgScore,
    tqa.TotalViews,
    ue.BadgeCount,
    ue.GoldBadges,
    ue.VotesCast,
    ue.CommentsPosted
HAVING COUNT(DISTINCT am.AnswerId) > 5
ORDER BY 
    (tqa.AvgScore * 0.3 + 
     ue.Reputation * 0.0001 + 
     COUNT(DISTINCT CASE WHEN am.AnswerRank = 1 THEN am.AnswerId END) * 0.4 + 
     ue.GoldBadges * 0.3) DESC
LIMIT 100;