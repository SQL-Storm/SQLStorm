WITH RankedAnswers AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score,
        u.Id AS OwnerUserId,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS "Rank",
        p.CreationDate
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
),
TopAnswers AS (
    SELECT * FROM RankedAnswers WHERE "Rank" = 1
),
QuestionStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount,
        AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore,
        COUNT(a.Id) AS TotalAnswers,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
        q.Tags AS RawTags
    FROM Posts q
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN LATERAL (
        SELECT value AS TagName
        FROM UNNEST(
            REGEXP_SPLIT_TO_ARRAY(
                SUBSTRING(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags) - 2)),
                '><'
            )
        ) AS value
    ) t ON true
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.Tags
),
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
ComplexResults AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.CreationDate AS QuestionCreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.UpVotesCount,
        qs.DownVotesCount,
        qs.AvgAnswerScore,
        qs.TotalAnswers,
        qs.Tags,
        ta.AnswerId,
        ta.Score AS TopAnswerScore,
        ta.OwnerUserId,
        u.Reputation AS AnswererReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ph.Comment AS CloseReason,
        pt.Name AS PostTypeName,
        qs.RawTags
    FROM QuestionStats qs
    LEFT JOIN TopAnswers ta ON qs.QuestionId = ta.QuestionId
    LEFT JOIN Users u ON ta.OwnerUserId = u.Id
    LEFT JOIN UserBadgeAgg ub ON ub.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = qs.QuestionId AND ph.PostHistoryTypeId = 10
    LEFT JOIN PostTypes pt ON pt.Id = (
        SELECT p2.PostTypeId FROM Posts p2 WHERE p2.Id = qs.QuestionId
    )
    WHERE qs.AnswerCount > 0 AND qs.ViewCount > 1000
    ORDER BY qs.ViewCount DESC
    LIMIT 50
)
SELECT 
    cr.QuestionId,
    cr.Title,
    cr.QuestionCreationDate,
    cr.QuestionScore,
    cr.ViewCount,
    cr.AnswerCount,
    cr.UpVotesCount,
    cr.DownVotesCount,
    cr.AvgAnswerScore,
    cr.TotalAnswers,
    cr.Tags,
    cr.AnswerId AS TopAnswerId,
    cr.TopAnswerScore,
    cr.OwnerUserId AS TopAnswerUserId,
    cr.AnswererReputation,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.CloseReason,
    cr.PostTypeName
FROM ComplexResults cr;