-- {"query": "46044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2228}

WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as QuestionCount,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(AVG(p.Score), 0) as AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName,
        COUNT(*) as PostsInTag,
        AVG(p.Score) as AvgTagScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as AcceptedQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, TagName
),
TopTagExperts AS (
    SELECT 
        te.*,
        t.Count as TagPopularity,
        ROW_NUMBER() OVER (PARTITION BY te.TagName ORDER BY te.PostsInTag DESC, te.AvgTagScore DESC) as ExpertRank
    FROM TagExpertise te
    JOIN Tags t ON te.TagName = t.TagName
    WHERE te.PostsInTag >= 3
),
AnswerPerformance AS (
    SELECT 
        a.Id as AnswerId,
        a.OwnerUserId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        q.CreationDate as QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as IsAccepted,
        q.ViewCount as QuestionViews,
        q.Score as QuestionScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) as AnswerComments
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND a.OwnerUserId IS NOT NULL
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
),
UserBadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges,
        COUNT(CASE WHEN b.TagBased = 1 THEN 1 END) as TagBasedBadges,
        MAX(b.Date) as LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
VotingPatterns AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as BountiesStarted,
        COALESCE(SUM(v.BountyAmount), 0) as TotalBountyAmount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
        AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY v.UserId
),
PostEditActivity AS (
    SELECT 
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as EditCount,
        COUNT(DISTINCT ph.PostId) as UniquePostsEdited,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 24 THEN 1 END) as SuggestedEditsApplied
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY ph.UserId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.TotalViews,
    ROUND(uem.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    ubm.TagBasedBadges,
    COALESCE(vp.UpvotesGiven, 0) as UpvotesGiven,
    COALESCE(vp.DownvotesGiven, 0) as DownvotesGiven,
    COALESCE(vp.BountiesStarted, 0) as BountiesStarted,
    COALESCE(vp.TotalBountyAmount, 0) as TotalBountySpent,
    COALESCE(pea.EditCount, 0) as TotalEdits,
    COALESCE(pea.UniquePostsEdited, 0) as UniquePostsEdited,
    COUNT(DISTINCT tte.TagName) as ExpertTagCount,
    STRING_AGG(DISTINCT CASE WHEN tte.ExpertRank <= 10 THEN tte.TagName END, ', ' ORDER BY CASE WHEN tte.ExpertRank <= 10 THEN tte.TagName END) as TopExpertiseTags,
    AVG(ap.AnswerScore) as AvgAnswerScore,
    AVG(ap.HoursToAnswer) as AvgHoursToAnswer,
    SUM(ap.IsAccepted)::float / NULLIF(COUNT(ap.AnswerId), 0) * 100 as AcceptanceRate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ap.AnswerScore) as MedianAnswerScore,
    MAX(ap.AnswerScore) as BestAnswerScore,
    SUM(CASE WHEN ap.HoursToAnswer < 1 THEN 1 ELSE 0 END) as QuickAnswersUnderOneHour
FROM UserEngagementMetrics uem
LEFT JOIN UserBadgeMetrics ubm ON uem.Id = ubm.UserId
LEFT JOIN VotingPatterns vp ON uem.Id = vp.UserId
LEFT JOIN PostEditActivity pea ON uem.Id = pea.UserId
LEFT JOIN TopTagExperts tte ON uem.Id = tte.OwnerUserId AND tte.ExpertRank <= 10
LEFT JOIN AnswerPerformance ap ON uem.Id = ap.OwnerUserId
WHERE uem.Reputation > 1000
GROUP BY 
    uem.Id, uem.DisplayName, uem.Reputation, uem.QuestionCount, uem.AnswerCount,
    uem.TotalViews, uem.AvgQuestionScore, ubm.GoldBadges, ubm.SilverBadges,
    ubm.BronzeBadges, ubm.TagBasedBadges, vp.UpvotesGiven, vp.DownvotesGiven,
    vp.BountiesStarted, vp.TotalBountyAmount, pea.EditCount, pea.UniquePostsEdited
HAVING COUNT(DISTINCT tte.TagName) >= 2
ORDER BY 
    uem.Reputation DESC,
    AvgAnswerScore DESC,
    AcceptanceRate DESC
LIMIT 100;
