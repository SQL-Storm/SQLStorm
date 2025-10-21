-- {"query": "47091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 208754, "output_tokens": 185435} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as AnswerScore,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as Tag,
        COUNT(*) as TagCount,
        SUM(p.Score) as TagScore
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, Tag
),
RankedTags AS (
    SELECT 
        OwnerUserId,
        Tag,
        TagCount,
        TagScore,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagScore DESC, TagCount DESC) as rn
    FROM TopTags
),
EditActivity AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as EditedPosts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as Edits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) as Rollbacks
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
),
VotePatterns AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as BountiesStarted,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyAmount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
AcceptanceRates AS (
    SELECT 
        q.OwnerUserId,
        COUNT(q.Id) as QuestionsAsked,
        COUNT(q.AcceptedAnswerId) as QuestionsWithAcceptedAnswer,
        CAST(COUNT(q.AcceptedAnswerId) AS FLOAT) / NULLIF(COUNT(q.Id), 0) as AcceptanceRate
    FROM Posts q
    WHERE q.PostTypeId = 1
        AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
    HAVING COUNT(q.Id) >= 5
),
ResponseTimes AS (
    SELECT 
        a.OwnerUserId,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600) as AvgResponseTimeHours,
        MIN(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60) as FastestResponseMinutes,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600) as MedianResponseHours
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
        AND a.OwnerUserId IS NOT NULL
        AND a.CreationDate > q.CreationDate
    GROUP BY a.OwnerUserId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.TotalPosts,
    um.Questions,
    um.Answers,
    ROUND(CAST(um.Answers AS FLOAT) / NULLIF(um.Questions, 0), 2) as AnswerQuestionRatio,
    um.QuestionScore,
    um.AnswerScore,
    um.QuestionScore + um.AnswerScore as TotalScore,
    ROUND(CAST(um.QuestionScore AS FLOAT) / NULLIF(um.Questions, 0), 2) as AvgQuestionScore,
    ROUND(CAST(um.AnswerScore AS FLOAT) / NULLIF(um.Answers, 0), 2) as AvgAnswerScore,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    STRING_AGG(DISTINCT rt.Tag || ' (' || rt.TagScore || ')', ', ' ORDER BY rt.Tag) FILTER (WHERE rt.rn <= 3) as Top3Tags,
    COALESCE(ea.Edits, 0) as TotalEdits,
    COALESCE(ea.Rollbacks, 0) as TotalRollbacks,
    COALESCE(vp.UpvotesGiven, 0) as UpvotesGiven,
    COALESCE(vp.DownvotesGiven, 0) as DownvotesGiven,
    COALESCE(vp.BountiesStarted, 0) as BountiesStarted,
    COALESCE(vp.TotalBountyAmount, 0) as TotalBountyAmount,
    ROUND(ar.AcceptanceRate * 100, 1) as AcceptanceRatePercent,
    ROUND(rt2.AvgResponseTimeHours, 1) as AvgResponseTimeHours,
    ROUND(rt2.MedianResponseHours, 1) as MedianResponseHours
FROM UserMetrics um
LEFT JOIN RankedTags rt ON um.Id = rt.OwnerUserId
LEFT JOIN EditActivity ea ON um.Id = ea.UserId
LEFT JOIN VotePatterns vp ON um.Id = vp.UserId
LEFT JOIN AcceptanceRates ar ON um.Id = ar.OwnerUserId
LEFT JOIN ResponseTimes rt2 ON um.Id = rt2.OwnerUserId
WHERE um.Reputation > 5000
    AND um.TotalPosts > 50
    AND (um.Questions > 10 OR um.Answers > 20)
GROUP BY 
    um.Id, um.DisplayName, um.Reputation, um.TotalPosts, um.Questions, um.Answers,
    um.QuestionScore, um.AnswerScore, um.GoldBadges, um.SilverBadges, um.BronzeBadges,
    ea.Edits, ea.Rollbacks, vp.UpvotesGiven, vp.DownvotesGiven, 
    vp.BountiesStarted, vp.TotalBountyAmount, ar.AcceptanceRate,
    rt2.AvgResponseTimeHours, rt2.MedianResponseHours
ORDER BY um.Reputation DESC, (um.QuestionScore + um.AnswerScore) DESC
LIMIT 100;
