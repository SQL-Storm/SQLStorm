WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        1 AS Level,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired
    FROM Tags t
    WHERE t.IsRequired = TRUE
    UNION ALL
    SELECT 
        child.Id,
        child.TagName,
        parent.Level + 1,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy parent ON child.IsModeratorOnly = parent.IsRequired
    WHERE child.Count < parent.Count
),
UserBadgeActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
TopPostsByComplexScore AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score * LOG(1 + p.ViewCount) DESC) AS Rank,
        LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS NextScore,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsInType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score IS NOT NULL
      AND p.ViewCount > 0
),
UserRecentActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(MAX(p.LastActivityDate), u.LastAccessDate) AS LastActiveDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        COUNT(c.Id) AS CommentsCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyGiven,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (8,9)
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate
),
PostLinksWithDuplicates AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.Score AS PostScore,
        p2.Score AS RelatedPostScore,
        CASE WHEN lt.Id = 3 THEN 1 ELSE 0 END AS IsDuplicateLink
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
),
FilteredQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        ph.CloseReasonId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS CloseDate
    FROM Posts p
    LEFT JOIN (
        SELECT 
            ph2.PostId, 
            CAST(ph2.Comment AS INTEGER) AS CloseReasonId, 
            ph2.PostHistoryTypeId,
            ph2.CreationDate
        FROM PostHistory ph2
        WHERE ph2.PostHistoryTypeId = 10
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
      AND (ph.CreationDate IS NULL OR ph.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
),
QuestionsWithDuplicates AS (
    SELECT DISTINCT
        fq.Id,
        fq.Title,
        fq.OwnerUserId,
        fq.Score,
        fq.ViewCount,
        fq.Tags,
        fq.AcceptedAnswerId,
        pl.RelatedPostId AS DuplicateOf,
        fq.CloseReasonId
    FROM FilteredQuestions fq
    LEFT JOIN PostLinksWithDuplicates pl ON pl.PostId = fq.Id AND pl.IsDuplicateLink = 1
),
FinalSelection AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        u.DisplayName AS OwnerName,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        ba.DisplayName AS AcceptedAnswerOwner,
        q.DuplicateOf,
        crt.Name AS CloseReason,
        uba.TotalBadges,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        ura.LastActiveDate,
        ura.QuestionsCount,
        ura.AnswersCount,
        ura.CommentsCount,
        ura.TotalBountyGiven,
        ura.AvgAnswerScore
    FROM QuestionsWithDuplicates q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    LEFT JOIN Users ba ON ba.Id = a.OwnerUserId
    LEFT JOIN UserBadgeActivity uba ON uba.UserId = q.OwnerUserId
    LEFT JOIN CloseReasonTypes crt ON crt.Id = q.CloseReasonId
    LEFT JOIN UserRecentActivity ura ON ura.UserId = q.OwnerUserId
    WHERE q.Score > (
        SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1
    )
)
SELECT 
    fs.QuestionId,
    fs.Title,
    fs.OwnerName,
    fs.QuestionScore,
    fs.ViewCount,
    CASE 
        WHEN fs.Tags IS NOT NULL AND POSITION('><' IN fs.Tags) > 0 THEN 
            SUBSTRING(fs.Tags FROM 2 FOR POSITION('><' IN fs.Tags)-2)
        WHEN fs.Tags IS NOT NULL THEN 
            SUBSTRING(fs.Tags FROM 2 FOR LENGTH(fs.Tags)-2)
        ELSE NULL
    END AS PrimaryTag,
    fs.AcceptedAnswerId,
    fs.AcceptedAnswerScore,
    fs.AcceptedAnswerOwner,
    fs.DuplicateOf,
    COALESCE(fs.CloseReason, 'Open') AS CloseReason,
    fs.TotalBadges,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.LastActiveDate,
    fs.QuestionsCount,
    fs.AnswersCount,
    fs.CommentsCount,
    fs.TotalBountyGiven,
    ROUND(CAST(fs.AvgAnswerScore AS NUMERIC),2) AS AvgAnswerScore,
    LENGTH(fs.Title) * COALESCE(NULLIF(fs.QuestionScore,0),1) * (fs.QuestionsCount + 1) / NULLIF(fs.ViewCount,1) AS ComplexityIndex
FROM FinalSelection fs
ORDER BY fs.QuestionScore DESC, fs.ViewCount DESC
LIMIT 100;