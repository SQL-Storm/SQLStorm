WITH Recursive_Tag_CTE AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count, 
        p.Id AS ExcerptPostId,
        p.Title AS ExcerptTitle,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = FALSE

    UNION ALL

    SELECT 
        t2.Id, 
        t2.TagName, 
        t2.Count,
        p2.Id AS ExcerptPostId,
        p2.Title AS ExcerptTitle,
        1 AS rn
    FROM Tags t2
    LEFT JOIN Posts p2 ON t2.WikiPostId = p2.Id
    WHERE t2.IsRequired = TRUE
),
User_Badge_Summary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS TagBasedBadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
Post_Activity_Window AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS RankByUserScore,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsByType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CloseReasonCounts AS (
    SELECT
        cht.Name AS CloseReasonName,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    JOIN PostHistoryTypes chtt ON ph.PostHistoryTypeId = chtt.Id
    JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INTEGER) = cht.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Name
),
DuplicateRelations AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
User_Answer_Acceptance AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 END) AS AcceptedAnswersCount,
        COUNT(*) AS TotalAnswers
    FROM Posts p
    LEFT JOIN Posts q ON p.Id = q.AcceptedAnswerId AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
Complex_User_Post_Stats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ua.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ua.AcceptedAnswersCount, 0) AS AcceptedAnswers,
        s.GoldBadges,
        s.SilverBadges,
        s.BronzeBadges,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        CASE 
            WHEN MAX(p.Score) > 50 THEN 'Expert'
            WHEN MAX(p.Score) BETWEEN 20 AND 50 THEN 'Intermediate'
            ELSE 'Novice'
        END AS ExpertiseLevel
    FROM Users u
    LEFT JOIN User_Badge_Summary s ON s.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    LEFT JOIN User_Answer_Acceptance ua ON ua.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, s.GoldBadges, s.SilverBadges, s.BronzeBadges, ua.TotalAnswers, ua.AcceptedAnswersCount
),
FinalSelectedPosts AS (
    SELECT p.*,
        u.DisplayName AS OwnerName,
        COALESCE(ph_max.MaxEditDate, p.LastEditDate) AS LastModifiedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS GlobalRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, MAX(CreationDate) AS MaxEditDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6,7,8,9)
        GROUP BY PostId
    ) ph_max ON ph_max.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
Correlated_Comment_Counts AS (
    SELECT
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score >= 5) AS HighScoreComments,
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS UniqueCommenters
    FROM Posts p
    WHERE p.PostTypeId = 1
),
CombinedResults AS (
    SELECT 
        fsp.Id AS PostId,
        fsp.Title,
        fsp.PostTypeId,
        fsp.Score,
        fsp.ViewCount,
        fsp.CreationDate,
        fsp.LastModifiedDate,
        fsp.OwnerUserId,
        fsp.OwnerName,
        cc.HighScoreComments,
        cc.UniqueCommenters,
        uc.ExpertiseLevel,
        uc.GoldBadges,
        uc.SilverBadges,
        uc.BronzeBadges,
        COALESCE(dr.RelatedPostId, 0) AS DuplicateOf,
        COALESCE(crc.CloseCount, 0) AS CloseCount,
        rt.Name AS PostTypeName,
        CASE 
            WHEN fsp.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            ELSE 'No Accepted Answer'
        END AS AcceptStatus,
        SUBSTRING(
            REPLACE(
                COALESCE(fsp.Tags, ''), '<', '|'
            ) FROM 1 FOR 100
        ) AS SampleTags
    FROM FinalSelectedPosts fsp
    LEFT JOIN Correlated_Comment_Counts cc ON cc.PostId = fsp.Id
    LEFT JOIN Complex_User_Post_Stats uc ON uc.UserId = fsp.OwnerUserId
    LEFT JOIN DuplicateRelations dr ON dr.PostId = fsp.Id
    LEFT JOIN CloseReasonCounts crc ON 1=1
    LEFT JOIN PostTypes rt ON rt.Id = fsp.PostTypeId
    WHERE fsp.GlobalRank <= 100
    ORDER BY fsp.Score DESC NULLS LAST, fsp.ViewCount DESC NULLS LAST
)
SELECT *
FROM CombinedResults
WHERE (
    (GoldBadges > 0 AND ExpertiseLevel = 'Expert')
    OR (HighScoreComments > 10)
    OR (DuplicateOf <> 0 AND AcceptStatus = 'No Accepted Answer')
)
AND (SampleTags IS NOT NULL AND LENGTH(SampleTags) > 5)
UNION
SELECT 
    Id AS PostId,
    Title,
    PostTypeId,
    Score,
    ViewCount,
    CreationDate,
    LastEditDate AS LastModifiedDate,
    OwnerUserId,
    OwnerDisplayName AS OwnerName,
    0 AS HighScoreComments,
    0 AS UniqueCommenters,
    'Novice' AS ExpertiseLevel,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS DuplicateOf,
    0 AS CloseCount,
    (SELECT Name FROM PostTypes WHERE Id = Posts.PostTypeId) AS PostTypeName,
    'No Accepted Answer' AS AcceptStatus,
    NULL AS SampleTags
FROM Posts
WHERE PostTypeId = 2
  AND Score < 0
ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST
LIMIT 200;