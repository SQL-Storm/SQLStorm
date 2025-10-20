WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews,
        MAX(p.CreationDate) as LastQuestionDate
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerMetrics AS (
    SELECT 
        a.ParentId as QuestionId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        MAX(a.Score) as BestAnswerScore,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) as UniqueAnswerers,
        MAX(a.CreationDate) - MIN(a.CreationDate) as TimeSpan
    FROM Posts a
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY a.ParentId
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Id as TagId,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgTagScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as AcceptedAnswerCount
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name
    INNER JOIN Tags t ON t.TagName = tag_name
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY t.TagName, t.Id
    HAVING COUNT(DISTINCT p.Id) >= 100
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT v.Id) as VotesCast,
        COUNT(DISTINCT c.Id) as CommentsPosted,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    tqa.DisplayName as AuthorName,
    tqa.QuestionCount,
    ROUND(CAST(tqa.AvgScore AS numeric), 2) as AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(am.AnswerCount, 0) as TotalAnswersReceived,
    COALESCE(ROUND(CAST(am.AvgAnswerScore AS numeric), 2), 0) as AvgAnswerScore,
    COALESCE(am.UniqueAnswerers, 0) as UniqueAnswerers,
    tp.TagName as MostUsedTag,
    ROUND(CAST(tp.AvgTagScore AS numeric), 2) as TagAvgScore,
    ue.Reputation,
    ue.VotesCast,
    ue.CommentsPosted,
    ue.BadgesEarned,
    ue.GoldBadges,
    ue.SilverBadges,
    RANK() OVER (ORDER BY tqa.QuestionCount DESC, tqa.AvgScore DESC) as AuthorRank,
    PERCENT_RANK() OVER (ORDER BY tqa.TotalViews) as ViewPercentile,
    LAG(tqa.AvgScore, 1) OVER (PARTITION BY tp.TagName ORDER BY tqa.QuestionCount DESC) as PrevAuthorAvgScore
FROM TopQuestionAuthors tqa
INNER JOIN UserEngagement ue ON tqa.OwnerUserId = ue.UserId
LEFT JOIN LATERAL (
    SELECT p.Id, p.Tags, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score
    FROM Posts p
    WHERE p.OwnerUserId = tqa.OwnerUserId
        AND p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    ORDER BY p.Score DESC
    LIMIT 1
) recent_post ON true
CROSS JOIN LATERAL unnest(string_to_array(substring(recent_post.Tags, 2, length(recent_post.Tags)-2), '><')) as main_tag
INNER JOIN TagPerformance tp ON tp.TagName = main_tag
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
) am ON true
WHERE ue.Reputation > 1000
    AND ue.VotesCast > 50
ORDER BY tqa.QuestionCount DESC, tqa.AvgScore DESC, tp.AvgTagScore DESC
LIMIT 100;