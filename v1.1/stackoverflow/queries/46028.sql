WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionQualityMetrics AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate AS QuestionCreationDate,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(DISTINCT pl2.Id) FILTER (WHERE pl2.LinkTypeId = 3) AS DuplicateCount,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS TagList,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600 AS HoursActive
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostLinks pl2 ON p.Id = pl2.RelatedPostId AND pl2.LinkTypeId = 3
    LEFT JOIN (
        SELECT p_inner.Id AS pid, unnest(string_to_array(substring(p_inner.Tags, 2, length(p_inner.Tags)-2), '><')) AS TagName
        FROM Posts p_inner
    ) tag_array ON tag_array.pid = p.Id
    LEFT JOIN Tags t ON t.TagName = tag_array.TagName
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '18 months'
        AND p.Score >= 0
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
             p.FavoriteCount, p.CreationDate, p.AcceptedAnswerId, p.LastActivityDate
),
AnswerPerformance AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        COUNT(DISTINCT c.Id) AS AnswerCommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAnswer,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN PostHistory ph ON a.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '18 months'
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.AcceptedAnswerId, q.CreationDate
),
RankedUsers AS (
    SELECT 
        uem.*,
        DENSE_RANK() OVER (ORDER BY uem.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY uem.TotalPosts DESC) AS PostPercentile,
        AVG(qqm.QuestionScore) AS AvgQuestionScore,
        AVG(ap.AnswerScore) AS AvgAnswerScore,
        SUM(CASE WHEN ap.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        AVG(ap.HoursToAnswer) AS AvgHoursToAnswer,
        COUNT(DISTINCT qqm.QuestionId) FILTER (WHERE qqm.ViewCount > 1000) AS HighViewQuestions
    FROM UserEngagementMetrics uem
    LEFT JOIN QuestionQualityMetrics qqm ON uem.UserId = qqm.OwnerUserId
    LEFT JOIN AnswerPerformance ap ON uem.UserId = ap.AnswererUserId
    GROUP BY uem.UserId, uem.DisplayName, uem.Reputation, uem.UserCreationDate, 
             uem.TotalPosts, uem.QuestionCount, uem.AnswerCount, uem.AvgPostScore,
             uem.TotalViews, uem.CommentCount, uem.BadgeCount, uem.GoldBadges,
             uem.SilverBadges, uem.BronzeBadges
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.ReputationRank,
    ru.TotalPosts,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AcceptedAnswerCount,
    ROUND(CAST(ru.AvgQuestionScore AS numeric), 2) AS AvgQuestionScore,
    ROUND(CAST(ru.AvgAnswerScore AS numeric), 2) AS AvgAnswerScore,
    ru.TotalViews,
    ru.CommentCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.HighViewQuestions,
    ROUND(CAST(ru.AvgHoursToAnswer AS numeric), 2) AS AvgHoursToAnswer,
    ROUND(CAST(ru.PostPercentile AS numeric), 4) AS PostPercentile,
    ROUND(
      CAST(ru.Reputation AS numeric) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01' AS date) - ru.UserCreationDate))/86400, 0)
    , 2) AS ReputationPerDay,
    CASE 
        WHEN ru.AnswerCount > 0 THEN ROUND((CAST(ru.AcceptedAnswerCount AS numeric) / ru.AnswerCount) * 100, 2)
        ELSE 0 
    END AS AcceptanceRate
FROM RankedUsers ru
WHERE ru.TotalPosts >= 10
    AND ru.Reputation > 500
ORDER BY ru.Reputation DESC, ru.TotalPosts DESC
LIMIT 500;