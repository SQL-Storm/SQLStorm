WITH TopQuestionContributors AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
      AND p.Score > 5
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerEngagement AS (
    SELECT 
        a.OwnerUserId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) AS AcceptedAnswers,
        COUNT(DISTINCT c.Id) AS CommentsOnAnswers
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    GROUP BY a.OwnerUserId
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        -- Standardize tag extraction without using :: casts or array literals
        REGEXP_SPLIT_TO_TABLE(
            TRIM(BOTH '[]' FROM p.Tags),
            '><'
        ) AS TagName,
        COUNT(DISTINCT p.Id) AS PostsInTags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.Score >= 3
    GROUP BY p.OwnerUserId, p.Tags
),
TagStats AS (
    SELECT 
        te.OwnerUserId,
        te.TagName,
        SUM(te.PostsInTags) AS TagPostCount
    FROM TagExpertise te
    GROUP BY te.OwnerUserId, te.TagName
),
UserBadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    GROUP BY b.UserId
),
EditHistory AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPosts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    GROUP BY ph.UserId
),
VoteActivity AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountiesStarted,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
      AND v.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    GROUP BY v.UserId
)
SELECT 
    tqc.DisplayName,
    tqc.Reputation,
    tqc.QuestionCount,
    ROUND(CAST(tqc.AvgQuestionScore AS NUMERIC), 2) AS AvgQuestionScore,
    tqc.TotalViews,
    COALESCE(ae.AnswerCount, 0) AS AnswerCount,
    ROUND(CAST(COALESCE(ae.AvgAnswerScore, 0) AS NUMERIC), 2) AS AvgAnswerScore,
    COALESCE(ae.AcceptedAnswers, 0) AS AcceptedAnswers,
    ROUND(
        COALESCE(CAST(ae.AcceptedAnswers AS NUMERIC) / NULLIF(CAST(ae.AnswerCount AS NUMERIC), 0), 0) * 100,
        2
    ) AS AcceptanceRate,
    COALESCE(ae.CommentsOnAnswers, 0) AS CommentsReceived,
    COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(eh.EditedPosts, 0) AS PostsEdited,
    COALESCE(eh.EditCount, 0) AS TotalEdits,
    COALESCE(va.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(va.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(va.BountiesStarted, 0) AS BountiesStarted,
    COALESCE(va.TotalBountyAmount, 0) AS TotalBountyAmount,
    (SELECT COUNT(DISTINCT ts.TagName)
     FROM TagStats ts
     WHERE ts.OwnerUserId = tqc.UserId AND ts.TagPostCount >= 5) AS ExpertTagCount,
    (SELECT STRING_AGG(ts.TagName, ', ' ORDER BY ts.TagPostCount DESC)
     FROM (
         SELECT TagName, TagPostCount
         FROM TagStats
         WHERE OwnerUserId = tqc.UserId
         ORDER BY TagPostCount DESC
         LIMIT 5
     ) ts) AS TopTags,
    ROUND(
        (tqc.QuestionCount +
         COALESCE(ae.AnswerCount, 0) +
         COALESCE(eh.EditCount, 0) * 0.5 +
         COALESCE(ubm.GoldBadges, 0) * 10 +
         COALESCE(ubm.SilverBadges, 0) * 5 +
         COALESCE(ubm.BronzeBadges, 0) * 2
        )::NUMERIC, 2
    ) AS EngagementScore
FROM TopQuestionContributors tqc
LEFT JOIN AnswerEngagement ae ON tqc.UserId = ae.OwnerUserId
LEFT JOIN UserBadgeMetrics ubm ON tqc.UserId = ubm.UserId
LEFT JOIN EditHistory eh ON tqc.UserId = eh.UserId
LEFT JOIN VoteActivity va ON tqc.UserId = va.UserId
WHERE tqc.Reputation > 1000
GROUP BY
    tqc.UserId,
    tqc.DisplayName,
    tqc.Reputation,
    tqc.QuestionCount,
    tqc.AvgQuestionScore,
    tqc.TotalViews,
    ae.AnswerCount,
    ae.AvgAnswerScore,
    ae.AcceptedAnswers,
    ae.CommentsOnAnswers,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    eh.EditedPosts,
    eh.EditCount,
    va.UpvotesGiven,
    va.DownvotesGiven,
    va.BountiesStarted,
    va.TotalBountyAmount,
    (SELECT COUNT(DISTINCT ts.TagName)
     FROM TagStats ts
     WHERE ts.OwnerUserId = tqc.UserId AND ts.TagPostCount >= 5),
    (SELECT STRING_AGG(ts.TagName, ', ' ORDER BY ts.TagPostCount DESC)
     FROM (
         SELECT TagName, TagPostCount
         FROM TagStats
         WHERE OwnerUserId = tqc.UserId
         ORDER BY TagPostCount DESC
         LIMIT 5
     ) ts)
ORDER BY EngagementScore DESC, tqc.Reputation DESC
LIMIT 100;