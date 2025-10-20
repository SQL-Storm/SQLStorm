WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.Score, 0) AS TopPostScore,
        p.Id AS TopPostId,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY COALESCE(p.Score, 0) DESC) AS rn
    FROM
        Tags t
    LEFT JOIN LATERAL (
        SELECT p.Id, p.Score
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags LIKE '%' || t.TagName || '%'
        ORDER BY p.Score DESC
        LIMIT 1
    ) p ON TRUE
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreation,
        COUNT(a.Id) AS AnswerCount,
        AVG(CASE WHEN a.Score IS NOT NULL THEN a.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN a.Score IS NOT NULL THEN a.Score END) AS MaxAnswerScore,
        SUM(COALESCE(a.CommentCount,0)) AS TotalAnswerComments,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
UserActivityRank AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COALESCE(ua.AnswerCount,0) AS UserAnswerCount,
        COALESCE(ua.QuestionCount,0) AS UserQuestionCount,
        RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) ua ON ua.OwnerUserId = u.Id
),
ComplexPostHistoryAggregates AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS EditCount,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        -- STRING_AGG with ORDER BY and DISTINCT is not supported in some dialects; emulate by aggregation where available.
        STRING_AGG(ph.UserDisplayName, ', ') AS Editors,
        MAX(CASE WHEN ph.Comment LIKE '%rollback%' THEN 1 ELSE 0 END) = 1 AS HasRollback,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10,12) THEN 1 ELSE 0 END) AS CloseOrDeleteVotes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12)
    GROUP BY ph.PostId, ph.PostHistoryTypeId
),
FinalResult AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.DistinctBadges,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.TotalAnswerComments,
        pas.LastAnswerDate,
        phag.EditCount,
        phag.FirstEditDate,
        phag.LastEditDate,
        phag.Editors,
        phag.HasRollback,
        phag.CloseOrDeleteVotes,
        rh.TagName,
        rh.TopPostId,
        rh.TopPostScore,
        uar.ReputationRank,
        CASE
            WHEN p.Tags IS NOT NULL THEN
                'Tags: ' || REPLACE(REPLACE(p.Tags, '><', ', '), '<', '') || '>'
            ELSE 'No Tags'
        END AS TagList,
        (p.Score * 1.5) + (COALESCE(u.Reputation,0)/1000.0) + (COALESCE(us.GoldBadges,0)*2) + (CASE WHEN phag.HasRollback THEN -5 ELSE 0 END) AS WeightedPostScore,
        RANK() OVER (PARTITION BY rh.TagName ORDER BY ((p.Score * 1.5) + (COALESCE(u.Reputation,0)/1000.0) + (COALESCE(us.GoldBadges,0)*2) + (CASE WHEN phag.HasRollback THEN -5 ELSE 0 END)) DESC) AS TagRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeStats us ON us.UserId = u.Id
    LEFT JOIN PostAnswerStats pas ON pas.QuestionId = p.Id
    LEFT JOIN ComplexPostHistoryAggregates phag ON phag.PostId = p.Id
    LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName IS NOT NULL AND p.Tags LIKE '%' || rh.TagName || '%'
    LEFT JOIN UserActivityRank uar ON uar.Id = u.Id
    WHERE p.PostTypeId = 1
)
SELECT *
FROM FinalResult
WHERE TagRank <= 5
  AND WeightedPostScore > 10

UNION ALL

SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    COALESCE(u.DisplayName, 'Anonymous') AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS DistinctBadges,
    0 AS AnswerCount,
    NULL AS AvgAnswerScore,
    NULL AS MaxAnswerScore,
    0 AS TotalAnswerComments,
    NULL AS LastAnswerDate,
    0 AS EditCount,
    NULL AS FirstEditDate,
    NULL AS LastEditDate,
    NULL AS Editors,
    FALSE AS HasRollback,
    0 AS CloseOrDeleteVotes,
    NULL AS TagName,
    NULL AS TopPostId,
    NULL AS TopPostScore,
    NULL AS ReputationRank,
    'No Tags' AS TagList,
    p.Score AS WeightedPostScore,
    1 AS TagRank
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.Tags IS NULL
ORDER BY WeightedPostScore DESC, AnswerCount DESC, ViewCount DESC
LIMIT 100;