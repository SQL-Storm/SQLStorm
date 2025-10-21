WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastQuestionDate
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
        AND p.Score >= 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        MAX(a.Score) AS BestAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) AS UniqueAnswerers,
        MAX(a.CreationDate) - MIN(a.CreationDate) AS TimeSpan
    FROM Posts a
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    GROUP BY a.ParentId
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Id AS TagId,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT tag_name FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag_name
    ) AS _tag
    INNER JOIN Tags t ON t.TagName = _tag.tag_name
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    GROUP BY t.TagName, t.Id
    HAVING COUNT(DISTINCT p.Id) >= 100
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT v.Id) AS VotesCast,
        COUNT(DISTINCT c.Id) AS CommentsPosted,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    WHERE u.CreationDate >= (DATE '2024-10-01' - INTERVAL '3' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    tqa.DisplayName AS AuthorName,
    tqa.QuestionCount,
    ROUND(tqa.AvgScore, 2) AS AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(am.AnswerCount, 0) AS TotalAnswersReceived,
    COALESCE(ROUND(am.AvgAnswerScore, 2), 0) AS AvgAnswerScore,
    COALESCE(am.UniqueAnswerers, 0) AS UniqueAnswerers,
    tp.TagName AS MostUsedTag,
    ROUND(tp.AvgTagScore, 2) AS TagAvgScore,
    ue.Reputation,
    ue.VotesCast,
    ue.CommentsPosted,
    ue.BadgesEarned,
    ue.GoldBadges,
    ue.SilverBadges,
    RANK() OVER (ORDER BY tqa.QuestionCount DESC, tqa.AvgScore DESC) AS AuthorRank,
    PERCENT_RANK() OVER (ORDER BY tqa.TotalViews) AS ViewPercentile,
    LAG(tqa.AvgScore, 1) OVER (PARTITION BY tp.TagName ORDER BY tqa.QuestionCount DESC) AS PrevAuthorAvgScore
FROM TopQuestionAuthors tqa
INNER JOIN UserEngagement ue ON tqa.OwnerUserId = ue.UserId
LEFT JOIN LATERAL (
    SELECT p.Id, p.Tags
    FROM Posts p
    WHERE p.OwnerUserId = tqa.OwnerUserId
        AND p.PostTypeId = 1
        AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
    ORDER BY p.Score DESC
    LIMIT 1
) AS recent_post (Id, Tags) ON TRUE
CROSS JOIN LATERAL (
    SELECT tag_name
    FROM unnest(string_to_array(substring(recent_post.Tags, 2, length(recent_post.Tags) - 2), '><')) AS tag_name
) AS main_tag
INNER JOIN TagPerformance tp ON tp.TagName = main_tag.tag_name
LEFT JOIN LATERAL (
    SELECT 
        am.AnswerCount,
        am.AvgAnswerScore,
        am.UniqueAnswerers
    FROM Posts p2
    INNER JOIN AnswerMetrics am ON p2.Id = am.QuestionId
    WHERE p2.OwnerUserId = tqa.OwnerUserId
        AND p2.PostTypeId = 1
    ORDER BY p2.CreationDate DESC
    LIMIT 1
) AS am ON TRUE
WHERE ue.Reputation > 1000
    AND ue.VotesCast > 50
ORDER BY tqa.QuestionCount DESC, tqa.AvgScore DESC, tp.AvgTagScore DESC
LIMIT 100;