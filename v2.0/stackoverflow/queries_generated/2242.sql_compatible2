WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.ExcerptPostId, t.WikiPostId, 1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id
    WHERE r.Level < 2
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END),0) AS QuestionViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.Date > (CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY)
    GROUP BY b.UserId
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Score DESC
        ) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
),
DuplicateQuestionPairs AS (
    SELECT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        pl.CreationDate AS LinkCreatedAt,
        u.DisplayName AS DuplicateOwner,
        po.DisplayName AS OriginalOwner
    FROM PostLinks pl
    JOIN Posts dup ON dup.Id = pl.PostId AND dup.PostTypeId = 1
    JOIN Posts orig ON orig.Id = pl.RelatedPostId AND orig.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = dup.OwnerUserId
    LEFT JOIN Users po ON po.Id = orig.OwnerUserId
    WHERE pl.LinkTypeId = 3
),
HighImpactComments AS (
    SELECT 
        c.Id,
        c.PostId,
        c.Score,
        c.CreationDate,
        SUBSTRING(c.Text FROM 1 FOR 100) AS ShortText,
        u.DisplayName AS Commenter,
        p.Title AS PostTitle,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS CommentRank
    FROM Comments c
    LEFT JOIN Users u ON u.Id = c.UserId
    LEFT JOIN Posts p ON p.Id = c.PostId
    WHERE c.Score > 5
),
AggregatedUserInfo AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.QuestionsCount,
        ups.AnswersCount,
        ups.TotalScore,
        ups.QuestionViews,
        COALESCE(rbc.GoldBadges,0) AS GoldBadges,
        COALESCE(rbc.SilverBadges,0) AS SilverBadges,
        COALESCE(rbc.BronzeBadges,0) AS BronzeBadges,
        ups.LastPostDate,
        rbc.LastBadgeDate,
        CASE 
            WHEN ups.QuestionViews > 100000 THEN 'High'
            WHEN ups.QuestionViews > 10000 THEN 'Medium'
            ELSE 'Low'
        END AS VisibilityCategory,
        CASE 
            WHEN ups.AnswersCount = 0 THEN NULL
            ELSE ROUND(1.0 * ups.TotalScore / ups.AnswersCount,2)
        END AS AvgAnswerScore,
        CASE 
            WHEN COALESCE(rbc.GoldBadges,0) >= 5 THEN 'Elite'
            WHEN COALESCE(rbc.GoldBadges,0) > 0 THEN 'Influencer'
            ELSE 'Regular'
        END AS UserTier
    FROM UserPostStats ups
    LEFT JOIN RecentBadgeCounts rbc ON rbc.UserId = ups.UserId
)
SELECT 
    aui.UserId,
    aui.DisplayName,
    aui.UserTier,
    aui.VisibilityCategory,
    aui.QuestionsCount,
    aui.AnswersCount,
    aui.TotalScore,
    aui.AvgAnswerScore,
    aui.GoldBadges,
    aui.SilverBadges,
    aui.BronzeBadges,
    aui.LastPostDate,
    aui.LastBadgeDate,
    daq.DuplicateQuestionId,
    daq.OriginalQuestionId,
    daq.LinkCreatedAt,
    daq.DuplicateOwner,
    daq.OriginalOwner,
    paw.Id AS RecentPostId,
    paw.PostTypeId,
    paw.Score AS RecentPostScore,
    paw.ViewCount AS RecentPostViews,
    paw.CommentCount AS RecentPostComments,
    paw.UserPostRank,
    paw.PrevPostScore,
    paw.NextPostScore,
    hic.Id AS HighCommentId,
    hic.Score AS HighCommentScore,
    hic.ShortText AS HighCommentExcerpt,
    hic.Commenter,
    hic.PostTitle
FROM AggregatedUserInfo aui
LEFT JOIN DuplicateQuestionPairs daq ON daq.DuplicateOwner = aui.DisplayName
LEFT JOIN PostActivityWindow paw ON paw.OwnerUserId = aui.UserId AND paw.UserPostRank <= 3
LEFT JOIN HighImpactComments hic ON hic.PostId = paw.Id AND hic.CommentRank = 1
WHERE aui.QuestionsCount > 0
  AND (aui.LastPostDate > (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY) OR aui.LastBadgeDate > (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY))
  AND (paw.Score IS NULL OR paw.Score >= 0)
ORDER BY aui.UserTier DESC, aui.TotalScore DESC, paw.CreationDate DESC
LIMIT 100;