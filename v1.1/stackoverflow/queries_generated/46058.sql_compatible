WITH TopQuestionsByYear AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC) AS YearRank
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2015-01-01'
        AND p.Score > 10
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= TIMESTAMP '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViews,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 100
),
AnswerQuality AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.CreationDate AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer,
        COUNT(c.Id) AS CommentCount,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= TIMESTAMP '2018-01-01'
        AND q.PostTypeId = 1
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.CreationDate, q.AcceptedAnswerId
)
SELECT 
    tq.Year,
    tq.Id AS TopQuestionId,
    ue.DisplayName AS QuestionAuthor,
    ue.Reputation,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.AvgPostScore,
    ue.GoldBadges,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.AnswerCount AS NumAnswers,
    COUNT(DISTINCT aq.AnswerId) AS DetailedAnswerCount,
    AVG(aq.AnswerScore) AS AvgAnswerScore,
    AVG(aq.HoursToAnswer) AS AvgHoursToAnswer,
    SUM(aq.IsAccepted) AS AcceptedAnswers,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkedPostsCount,
    STRING_AGG(tp.TagName, ', ' ORDER BY tp.TagUsageCount DESC) AS RelatedTags,
    AVG(tp.AvgScore) AS AvgTagScore
FROM TopQuestionsByYear tq
INNER JOIN UserEngagement ue ON tq.OwnerUserId = ue.UserId
LEFT JOIN AnswerQuality aq ON tq.Id = aq.QuestionId
LEFT JOIN PostHistory ph ON tq.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN PostLinks pl ON tq.Id = pl.PostId
LEFT JOIN Posts p ON tq.Id = p.Id
CROSS JOIN LATERAL (
    SELECT t.TagName, tp2.TagUsageCount, tp2.AvgScore
    FROM Tags t
    INNER JOIN TagPopularity tp2 ON t.TagName = tp2.TagName
    WHERE p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
) tp
WHERE tq.YearRank <= 100
GROUP BY tq.Year, tq.Id, ue.DisplayName, ue.Reputation, ue.QuestionCount, 
         ue.AnswerCount, ue.AvgPostScore, ue.GoldBadges, tq.Score, tq.ViewCount, tq.AnswerCount
HAVING COUNT(DISTINCT aq.AnswerId) > 0
ORDER BY tq.Year DESC, tq.Score DESC, AvgAnswerScore DESC
LIMIT 1000;