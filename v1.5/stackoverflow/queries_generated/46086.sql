-- {"query": "46086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1933}

WITH TopQuestionContributors AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgQuestionScore,
        SUM(p.ViewCount) as TotalViews
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
        AND p.Score > 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerEngagement AS (
    SELECT 
        a.OwnerUserId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) as AcceptedAnswers,
        COUNT(DISTINCT c.Id) as CommentsOnAnswers
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY a.OwnerUserId
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        COUNT(DISTINCT p.Id) as PostsInTags
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.Score >= 3
    GROUP BY p.OwnerUserId, p.Tags
),
TagStats AS (
    SELECT 
        te.OwnerUserId,
        unnest(te.tag_array) as TagName,
        SUM(te.PostsInTags) as TagPostCount
    FROM TagExpertise te
    GROUP BY te.OwnerUserId, unnest(te.tag_array)
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
EditHistory AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as EditedPosts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) as EditCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY ph.UserId
),
VoteActivity AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as BountiesStarted,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyAmount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
        AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY v.UserId
)
SELECT 
    tqc.DisplayName,
    tqc.Reputation,
    tqc.QuestionCount,
    ROUND(tqc.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    tqc.TotalViews,
    COALESCE(ae.AnswerCount, 0) as AnswerCount,
    ROUND(COALESCE(ae.AvgAnswerScore, 0)::numeric, 2) as AvgAnswerScore,
    COALESCE(ae.AcceptedAnswers, 0) as AcceptedAnswers,
    ROUND(COALESCE(ae.AcceptedAnswers::numeric / NULLIF(ae.AnswerCount, 0), 0) * 100, 2) as AcceptanceRate,
    COALESCE(ae.CommentsOnAnswers, 0) as CommentsReceived,
    COALESCE(ubm.GoldBadges, 0) as GoldBadges,
    COALESCE(ubm.SilverBadges, 0) as SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) as BronzeBadges,
    COALESCE(eh.EditedPosts, 0) as PostsEdited,
    COALESCE(eh.EditCount, 0) as TotalEdits,
    COALESCE(va.UpvotesGiven, 0) as UpvotesGiven,
    COALESCE(va.DownvotesGiven, 0) as DownvotesGiven,
    COALESCE(va.BountiesStarted, 0) as BountiesStarted,
    COALESCE(va.TotalBountyAmount, 0) as TotalBountyAmount,
    (SELECT COUNT(DISTINCT ts.TagName) 
     FROM TagStats ts 
     WHERE ts.OwnerUserId = tqc.UserId AND ts.TagPostCount >= 5) as ExpertTagCount,
    (SELECT string_agg(ts.TagName, ', ' ORDER BY ts.TagPostCount DESC)
     FROM (SELECT TagName, TagPostCount 
           FROM TagStats 
           WHERE OwnerUserId = tqc.UserId 
           ORDER BY TagPostCount DESC 
           LIMIT 5) ts) as TopTags,
    ROUND((tqc.QuestionCount + COALESCE(ae.AnswerCount, 0) + COALESCE(eh.EditCount, 0) * 0.5 + 
           COALESCE(ubm.GoldBadges, 0) * 10 + COALESCE(ubm.SilverBadges, 0) * 5 + 
           COALESCE(ubm.BronzeBadges, 0) * 2)::numeric, 2) as EngagementScore
FROM TopQuestionContributors tqc
LEFT JOIN AnswerEngagement ae ON tqc.UserId = ae.OwnerUserId
LEFT JOIN UserBadgeMetrics ubm ON tqc.UserId = ubm.UserId
LEFT JOIN EditHistory eh ON tqc.UserId = eh.UserId
LEFT JOIN VoteActivity va ON tqc.UserId = va.UserId
WHERE tqc.Reputation > 1000
ORDER BY EngagementScore DESC, tqc.Reputation DESC
LIMIT 100;
