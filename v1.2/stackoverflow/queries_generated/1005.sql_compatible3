WITH RECURSIVE RecursiveTagDepths AS (
    SELECT
        t.Id,
        t.TagName,
        1 AS Depth,
        t.WikiPostId
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        d.Depth + 1,
        t2.WikiPostId
    FROM Tags t2
    JOIN RecursiveTagDepths d ON t2.ExcerptPostId = d.WikiPostId
    WHERE d.Depth < 5
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE(SUM(b.Class), 0) AS BadgeClassSum
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAggregates AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.Score / NULLIF(LOG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400 + 1), 0) AS NormalizedScore,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.ClosedDate IS NOT NULL THEN true ELSE false END AS AcceptedAndClosed,
        CONCAT(
            COALESCE(p.Title, 'No Title'),
            ' [',
            COALESCE(SPLIT_PART(TRIM(BOTH '<>' FROM p.Tags), '><', 1), 'NoTag'),
            ']?'
        ) AS TitleWithFirstTag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
AnswerWithContext AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Tags AS QuestionTags
    FROM Posts a
    LEFT JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
TopAnswererPerQuestion AS (
    SELECT DISTINCT ON (q.Id)
        q.Id AS QuestionId,
        q.Title,
        a.AnswerId,
        a.AnswerOwnerId,
        a.AnswerScore,
        a.AnswerCreation,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.AnswerId) AS AnswerCommentCount,
        CASE WHEN u.CreationDate < a.AnswerCreation - INTERVAL '2 years' THEN 1 ELSE 0 END AS ExperiencedUser
    FROM Posts q
    JOIN AnswerWithContext a ON a.QuestionId = q.Id
    JOIN Users u ON u.Id = a.AnswerOwnerId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    WHERE q.PostTypeId = 1
      AND a.AnswerScore = (
        SELECT MAX(a2.AnswerScore) FROM AnswerWithContext a2 WHERE a2.QuestionId = q.Id
      )
    ORDER BY q.Id, a.AnswerScore DESC, a.AnswerCreation ASC
),
CombinedSets AS (
    SELECT UserId, DisplayName, 'GoldUsers' AS Source FROM UserBadgeCounts WHERE GoldBadges > 5
    UNION
    SELECT UserId, DisplayName, 'SilverUsers' FROM UserBadgeCounts WHERE SilverBadges > 20
    EXCEPT
    SELECT UserId, DisplayName, 'GoldUsers' FROM UserBadgeCounts WHERE BronzeBadges < 10
)
SELECT
    tqd.QuestionId,
    tqd.Title AS QuestionTitle,
    tqd.AnswerId,
    tqd.DisplayName AS TopAnswererName,
    tqd.AnswerScore,
    tqd.GoldBadges,
    tqd.SilverBadges,
    tqd.BronzeBadges,
    tqd.AnswerCommentCount,
    tqd.ExperiencedUser,
    pagg.NormalizedScore AS QuestionNormalizedScore,
    pagg.TitleWithFirstTag,
    pagg.AcceptedAndClosed,
    -- aggregate distinct tag names without ORDER BY inside STRING_AGG; order in a subquery first
    STRING_AGG(rtd.TagName, ',') FILTER (WHERE rtd.Depth <= 3) AS RelatedTags,
    EXISTS (
        SELECT 1 FROM PostHistory ph
        WHERE ph.PostId = tqd.QuestionId
          AND ph.PostHistoryTypeId IN (17,35,36)
          AND ph.CreationDate > p.CreationDate
    ) AS WasMigrated,
    ROW_NUMBER() OVER (ORDER BY pagg.NormalizedScore DESC) AS GlobalQuestionRank
FROM TopAnswererPerQuestion tqd
JOIN PostAggregates pagg ON pagg.Id = tqd.QuestionId
LEFT JOIN (
    SELECT WikiPostId, TagName, Depth
    FROM RecursiveTagDepths
    WHERE Depth IS NOT NULL
    ORDER BY Depth, TagName
) rtd ON rtd.WikiPostId = pagg.Id
LEFT JOIN Posts p ON p.Id = tqd.QuestionId
WHERE tqd.AnswerScore > 10
  AND pagg.AcceptedAndClosed = false
  AND (tqd.GoldBadges + tqd.SilverBadges + tqd.BronzeBadges) >= 10
  AND tqd.ExperiencedUser = 1
GROUP BY
    tqd.QuestionId,
    tqd.Title,
    tqd.AnswerId,
    tqd.DisplayName,
    tqd.AnswerScore,
    tqd.GoldBadges,
    tqd.SilverBadges,
    tqd.BronzeBadges,
    tqd.AnswerCommentCount,
    tqd.ExperiencedUser,
    pagg.NormalizedScore,
    pagg.TitleWithFirstTag,
    pagg.AcceptedAndClosed,
    p.CreationDate
ORDER BY GlobalQuestionRank
LIMIT 100;