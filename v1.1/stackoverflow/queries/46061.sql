WITH TopQuestionAuthors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerEngagement AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT a.OwnerUserId) AS UniqueAnswerers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS BestAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS SelfAnswers
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY a.ParentId
),
TagPerformance AS (
    SELECT 
        t.tag,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        AVG(ae.AnswerCount) AS AvgAnswers,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
    LEFT JOIN AnswerEngagement ae ON p.Id = ae.QuestionId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY t.tag
    HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY b.UserId
),
VotingPatterns AS (
    SELECT 
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStarts,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY p.Id
)
SELECT 
    tqa.DisplayName AS AuthorName,
    tqa.Reputation,
    tqa.QuestionCount,
    ROUND(CAST(tqa.AvgQuestionScore AS numeric), 2) AS AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
    ROUND(CAST(AVG(ae.AnswerCount) AS numeric), 2) AS AvgAnswersPerQuestion,
    ROUND(CAST(AVG(ae.AvgAnswerScore) AS numeric), 2) AS AvgAnswerQuality,
    ROUND(CAST(AVG(CASE WHEN vp.DownVotes = 0 THEN NULL ELSE (CAST(vp.UpVotes AS numeric) / vp.DownVotes) END) AS numeric), 2) AS UpDownVoteRatio,
    SUM(vp.Favorites) AS TotalFavorites,
    SUM(vp.TotalBountyAmount) AS TotalBountyReceived,
    STRING_AGG(tp.tag, ', ' ORDER BY tp.tag) AS TopTags,
    ROUND(CAST(AVG(tp.AvgScore) AS numeric), 2) AS TagAvgScore,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer,
    ROUND(100.0 * COUNT(DISTINCT p.Id) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) / NULLIF(tqa.QuestionCount, 0), 2) AS AcceptanceRate
FROM TopQuestionAuthors tqa
INNER JOIN Posts p ON tqa.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN AnswerEngagement ae ON p.Id = ae.QuestionId
LEFT JOIN VotingPatterns vp ON p.Id = vp.PostId
LEFT JOIN UserBadgeMetrics ubm ON tqa.Id = ubm.UserId
CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS ptag(tag)
INNER JOIN TagPerformance tp ON ptag.tag = tp.tag
WHERE tp.QuestionCount >= 100
GROUP BY 
    tqa.Id,
    tqa.DisplayName, 
    tqa.Reputation, 
    tqa.QuestionCount, 
    tqa.AvgQuestionScore, 
    tqa.TotalViews,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    tp.tag
HAVING AVG(ae.AnswerCount) >= 2
ORDER BY 
    tqa.Reputation DESC,
    tqa.TotalViews DESC,
    ROUND(CAST(AVG(ae.AnswerCount) AS numeric), 2) DESC
LIMIT 100;