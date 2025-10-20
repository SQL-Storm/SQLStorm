WITH UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LastGoldBadgeDate,
        STRING_AGG(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Name ELSE NULL END, ', ') AS TagBasedBadges,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
      AND u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 YEAR'
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank,
        COALESCE(a.AnswersCount, 0) AS AnswerCount,
        COALESCE(cv.DuplicateCount, 0) AS DuplicateClosures,
        EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = p.Id 
              AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
        ) AS IsClosed
    FROM Posts p
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswersCount 
        FROM Posts 
        WHERE PostTypeId = 2 
        GROUP BY ParentId
    ) a ON a.ParentId = p.Id
    LEFT JOIN (
        SELECT pl.PostId, COUNT(*) AS DuplicateCount
        FROM PostLinks pl
        INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id AND lt.Name = 'Duplicate'
        GROUP BY pl.PostId
    ) cv ON cv.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.Score > 5
),
QuestionCommentsStats AS (
    SELECT
        pc.PostId,
        COUNT(pc.Id) AS CommentCount,
        AVG(pc.Score) AS AvgCommentScore,
        SUM(CASE WHEN pc.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
    FROM Comments pc
    WHERE pc.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 DAY'
    GROUP BY pc.PostId
),
UserActivityRanked AS (
    SELECT
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY PH.UserId ORDER BY PH.CreationDate DESC) AS RecentEditRank
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL AND PH.PostHistoryTypeId IN (4,5,6)
),
ComplexData AS (
    SELECT
        ubs.UserId,
        ubs.DisplayName,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastGoldBadgeDate,
        ubs.TagBasedBadges,
        ubs.AvgPostScore,
        tq.Id AS QuestionId,
        tq.Title,
        tq.CreationDate AS QuestionCreation,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        tq.Tags,
        tq.AnswerCount,
        tq.DuplicateClosures,
        tq.IsClosed,
        qcs.CommentCount,
        qcs.AvgCommentScore,
        qcs.AnonymousComments,
        uar.RecentEditRank,
        CASE 
            WHEN tq.IsClosed THEN CONCAT('CLOSED: ', COALESCE(NULLIF(tq.Tags, ''), 'NoTags'))
            ELSE CONCAT('Open - Views:', (CASE WHEN tq.Score = 0 THEN NULL ELSE CAST(tq.ViewCount AS VARCHAR) END), ' AvgBadgeScore:', ROUND(ubs.AvgPostScore, 2))
        END AS PostStatusSummary,
        (
            SELECT COUNT(*)
            FROM PostLinks pl2
            WHERE pl2.RelatedPostId = tq.Id
              AND pl2.LinkTypeId = 3
        ) AS BackLinksToThisQuestion,
        COALESCE(NULLIF(ubs.DisplayName, ''), 'UnknownUser') AS CleanDisplayName,
        tq.IsClosed AS IsClosed_for_grouping,
        tq.Score AS Score_for_grouping,
        tq.Title AS Title_for_grouping,
        ubs.AvgPostScore AS AvgPostScore_for_grouping,
        tq.ViewCount AS ViewCount_for_grouping
    FROM UserBadgeSummary ubs
    INNER JOIN TopQuestions tq ON tq.OwnerUserId = ubs.UserId AND tq.QuestionRank = 1
    LEFT JOIN QuestionCommentsStats qcs ON qcs.PostId = tq.Id
    LEFT JOIN UserActivityRanked uar ON uar.UserId = ubs.UserId AND uar.PostId = tq.Id AND uar.RecentEditRank = 1
    WHERE ubs.GoldBadges > 0
    GROUP BY
        ubs.UserId,
        ubs.DisplayName,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastGoldBadgeDate,
        ubs.TagBasedBadges,
        ubs.AvgPostScore,
        tq.Id,
        tq.Title,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        tq.AnswerCount,
        tq.DuplicateClosures,
        tq.IsClosed,
        qcs.CommentCount,
        qcs.AvgCommentScore,
        qcs.AnonymousComments,
        uar.RecentEditRank
)
SELECT 
    cd.UserId,
    cd.CleanDisplayName AS DisplayName,
    cd.TotalBadges,
    cd.GoldBadges,
    cd.SilverBadges,
    cd.BronzeBadges,
    cd.LastGoldBadgeDate,
    cd.TagBasedBadges,
    cd.QuestionId,
    CASE WHEN LENGTH(cd.Title) > 80 THEN SUBSTRING(cd.Title FROM 1 FOR 80) || '...' ELSE cd.Title END AS ShortTitle,
    cd.QuestionCreation,
    ROUND(CAST(cd.QuestionScore AS NUMERIC), 2) AS QuestionScore,
    cd.ViewCount,
    cd.AnswerCount,
    cd.DuplicateClosures,
    cd.CommentCount,
    cd.AvgCommentScore,
    cd.AnonymousComments,
    cd.PostStatusSummary,
    cd.BackLinksToThisQuestion,
    cd.RecentEditRank
FROM ComplexData cd
WHERE cd.IsClosed = FALSE
  AND (cd.AvgCommentScore IS NULL OR cd.AvgCommentScore > 0)
  AND cd.LastGoldBadgeDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 DAY'
UNION
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    0 AS TotalBadges,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS LastGoldBadgeDate,
    CAST(NULL AS VARCHAR) AS TagBasedBadges,
    NULL AS QuestionId,
    CAST(NULL AS VARCHAR) AS ShortTitle,
    CAST(NULL AS TIMESTAMP) AS QuestionCreation,
    CAST(NULL AS NUMERIC) AS QuestionScore,
    0 AS ViewCount,
    0 AS AnswerCount,
    0 AS DuplicateClosures,
    0 AS CommentCount,
    CAST(NULL AS NUMERIC) AS AvgCommentScore,
    0 AS AnonymousComments,
    CAST('User has no qualifying posts or badges' AS VARCHAR) AS PostStatusSummary,
    0 AS BackLinksToThisQuestion,
    0 AS RecentEditRank
FROM Users u
WHERE u.Reputation > 10000
  AND u.Id NOT IN (SELECT UserId FROM UserBadgeSummary)
ORDER BY GoldBadges DESC NULLS LAST, QuestionScore DESC NULLS LAST, UserId
LIMIT 100;