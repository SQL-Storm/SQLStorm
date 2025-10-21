-- {"query": "46061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1795}

WITH TopQuestionAuthors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgQuestionScore,
        SUM(p.ViewCount) as TotalViews
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
        AND p.Score >= 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerEngagement AS (
    SELECT 
        a.ParentId as QuestionId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COUNT(DISTINCT a.OwnerUserId) as UniqueAnswerers,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as BestAnswerScore,
        COUNT(DISTINCT c.Id) as TotalComments,
        SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) as SelfAnswers
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY a.ParentId
),
TagPerformance AS (
    SELECT 
        t.tag,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        AVG(ae.AnswerCount) as AvgAnswers,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as t(tag)
    LEFT JOIN AnswerEngagement ae ON p.Id = ae.QuestionId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY t.tag
    HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        COUNT(DISTINCT b.Name) as UniqueBadges
    FROM Badges b
    WHERE b.Date >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY b.UserId
),
VotingPatterns AS (
    SELECT 
        p.Id as PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as BountyStarts,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY p.Id
)
SELECT 
    tqa.DisplayName as AuthorName,
    tqa.Reputation,
    tqa.QuestionCount,
    ROUND(tqa.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ubm.GoldBadges, 0) as GoldBadges,
    COALESCE(ubm.SilverBadges, 0) as SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) as BronzeBadges,
    ROUND(AVG(ae.AnswerCount)::numeric, 2) as AvgAnswersPerQuestion,
    ROUND(AVG(ae.AvgAnswerScore)::numeric, 2) as AvgAnswerQuality,
    ROUND(AVG(vp.UpVotes::numeric / NULLIF(vp.DownVotes, 0)), 2) as UpDownVoteRatio,
    SUM(vp.Favorites) as TotalFavorites,
    SUM(vp.TotalBountyAmount) as TotalBountyReceived,
    STRING_AGG(DISTINCT tp.tag, ', ' ORDER BY tp.tag) as TopTags,
    ROUND(AVG(tp.AvgScore)::numeric, 2) as TagAvgScore,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) as QuestionsWithAcceptedAnswer,
    ROUND(100.0 * COUNT(DISTINCT p.Id) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) / NULLIF(tqa.QuestionCount, 0), 2) as AcceptanceRate
FROM TopQuestionAuthors tqa
INNER JOIN Posts p ON tqa.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN AnswerEngagement ae ON p.Id = ae.QuestionId
LEFT JOIN VotingPatterns vp ON p.Id = vp.PostId
LEFT JOIN UserBadgeMetrics ubm ON tqa.Id = ubm.UserId
CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as ptag(tag)
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
    ubm.BronzeBadges
HAVING AVG(ae.AnswerCount) >= 2
ORDER BY 
    tqa.Reputation DESC,
    tqa.TotalViews DESC,
    AvgAnswersPerQuestion DESC
LIMIT 100;
