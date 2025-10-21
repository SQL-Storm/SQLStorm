-- {"query": "47053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1649}

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as QuestionCount,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalQuestionScore,
        COALESCE(SUM(a.Score), 0) as TotalAnswerScore,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagExperts AS (
    SELECT 
        t.TagName,
        u.Id as UserId,
        COUNT(DISTINCT p.Id) as PostsInTag,
        SUM(p.Score) as TagScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 100
        AND p.Score > 0
    GROUP BY t.TagName, u.Id
    HAVING COUNT(DISTINCT p.Id) >= 10
),
EditPatterns AS (
    SELECT 
        ph.UserId,
        DATE_TRUNC('month', ph.CreationDate) as EditMonth,
        COUNT(*) as EditCount,
        COUNT(DISTINCT ph.PostId) as UniquePostsEdited,
        COUNT(DISTINCT DATE(ph.CreationDate)) as ActiveDays
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.UserId IS NOT NULL
        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
    GROUP BY ph.UserId, DATE_TRUNC('month', ph.CreationDate)
),
NetworkAnalysis AS (
    SELECT 
        p1.OwnerUserId as QuestionerId,
        p2.OwnerUserId as AnswererId,
        COUNT(DISTINCT p2.Id) as InteractionCount,
        AVG(p2.Score) as AvgAnswerScore,
        SUM(CASE WHEN p2.Id = p1.AcceptedAnswerId THEN 1 ELSE 0 END) as AcceptedAnswers
    FROM Posts p1
    JOIN Posts p2 ON p1.Id = p2.ParentId
    WHERE p1.PostTypeId = 1 
        AND p2.PostTypeId = 2
        AND p1.OwnerUserId IS NOT NULL
        AND p2.OwnerUserId IS NOT NULL
        AND p1.OwnerUserId != p2.OwnerUserId
    GROUP BY p1.OwnerUserId, p2.OwnerUserId
    HAVING COUNT(DISTINCT p2.Id) >= 3
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.QuestionCount,
    um.AnswerCount,
    ROUND(um.TotalQuestionScore::NUMERIC / NULLIF(um.QuestionCount, 0), 2) as AvgQuestionScore,
    ROUND(um.TotalAnswerScore::NUMERIC / NULLIF(um.AnswerCount, 0), 2) as AvgAnswerScore,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    STRING_AGG(DISTINCT 
        CASE WHEN te.TagRank = 1 THEN te.TagName END, 
        ', ' ORDER BY te.TagName
    ) as TopTagExpertise,
    COUNT(DISTINCT te.TagName) FILTER (WHERE te.TagRank <= 3) as Top3TagCount,
    COALESCE(AVG(ep.EditCount), 0) as AvgMonthlyEdits,
    COALESCE(MAX(ep.ActiveDays), 0) as MaxActiveDaysPerMonth,
    COUNT(DISTINCT na.AnswererId) as UniqueAnswerers,
    COUNT(DISTINCT na2.QuestionerId) as UniqueQuestioners,
    COALESCE(SUM(na.AcceptedAnswers), 0) as TotalAcceptedGiven,
    COALESCE(SUM(na2.AcceptedAnswers), 0) as TotalAcceptedReceived,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY na.AvgAnswerScore) as MedianAnswerScoreGiven,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY na2.AvgAnswerScore) as MedianAnswerScoreReceived
FROM UserMetrics um
LEFT JOIN TagExperts te ON um.Id = te.UserId AND te.TagRank <= 10
LEFT JOIN EditPatterns ep ON um.Id = ep.UserId
LEFT JOIN NetworkAnalysis na ON um.Id = na.QuestionerId
LEFT JOIN NetworkAnalysis na2 ON um.Id = na2.AnswererId
WHERE um.QuestionCount + um.AnswerCount > 50
GROUP BY 
    um.Id,
    um.DisplayName, 
    um.Reputation, 
    um.QuestionCount, 
    um.AnswerCount,
    um.TotalQuestionScore,
    um.TotalAnswerScore,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges
HAVING COUNT(DISTINCT te.TagName) > 0
ORDER BY 
    um.Reputation DESC,
    (um.TotalQuestionScore + um.TotalAnswerScore) DESC
LIMIT 100;
