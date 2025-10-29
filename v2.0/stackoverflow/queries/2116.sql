WITH RecursiveUserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC NULLS LAST) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b
        ON u.Id = b.UserId
    WHERE u.Reputation > 1000
),
TopBadges AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        Location,
        BadgeName,
        BadgeClass,
        BadgeDate
    FROM RecursiveUserBadgeStats
    WHERE BadgeRank <= 3
),
QuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL) AS OpenQuestions,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(COALESCE(p.FavoriteCount, 0)) FILTER (WHERE p.PostTypeId = 2) AS TotalFavoritesOnAnswers
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserCombinedStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(qs.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(qs.OpenQuestions, 0) AS OpenQuestions,
        COALESCE(qs.AvgQuestionScore, 0) AS AvgQuestionScore,
        COALESCE(qs.MaxQuestionViews, 0) AS MaxQuestionViews,
        COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.TotalFavoritesOnAnswers, 0) AS TotalFavoritesOnAnswers
    FROM Users u
    LEFT JOIN QuestionStats qs ON u.Id = qs.OwnerUserId
    LEFT JOIN AnswerStats ans ON u.Id = ans.OwnerUserId
    WHERE u.Reputation > 1000
),
PostCommentsSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentsCount,
        COUNT(DISTINCT c.UserId) FILTER (WHERE c.UserId IS NOT NULL) AS UniqueCommenters,
        MAX(c.CreationDate) AS LastCommentDate,
        -- Move the ORDER BY expression into the STRING_AGG argument list by using DISTINCT on the same expression
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS CommenterNames
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
PostsWithRatings AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        COALESCE(php.EditCount, 0) AS EditCount,
        pc.CommentsCount,
        pc.UniqueCommenters,
        pc.LastCommentDate,
        pc.CommenterNames,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6,7,8,9,14)
        GROUP BY PostId
    ) php ON p.Id = php.PostId
    LEFT JOIN PostCommentsSummary pc ON p.Id = pc.PostId
),
DuplicatePosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        CASE WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Linked' END AS LinkTypeName,
        p1.Title AS OriginalTitle,
        p2.Title AS RelatedTitle
    FROM PostLinks pl
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.LinkTypeId = 3
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.Location,
    ucs.TotalQuestions,
    ucs.OpenQuestions,
    ROUND(CAST(ucs.AvgQuestionScore AS NUMERIC), 2) AS AvgQuestionScore,
    ucs.MaxQuestionViews,
    ucs.TotalAnswers,
    ROUND(CAST(ucs.AvgAnswerScore AS NUMERIC), 2) AS AvgAnswerScore,
    ucs.TotalFavoritesOnAnswers,
    tb.BadgeName,
    tb.BadgeClass,
    tb.BadgeDate,
    pwr.Id AS PostId,
    pwr.PostTypeId,
    pwr.Title AS PostTitle,
    COALESCE(pwr.Tags, '') AS PostTags,
    pwr.CreationDate,
    pwr.Score,
    pwr.ViewCount,
    pwr.UpVotes,
    pwr.DownVotes,
    pwr.EditCount,
    pwr.CommentsCount,
    pwr.UniqueCommenters,
    pwr.LastCommentDate,
    pwr.CommenterNames,
    pwr.PostStatus,
    dup.RelatedPostId AS DuplicateOfPostId,
    dup.RelatedTitle AS DuplicateOfPostTitle
FROM UserCombinedStats ucs
LEFT JOIN TopBadges tb ON ucs.UserId = tb.UserId
LEFT JOIN PostsWithRatings pwr ON ucs.UserId = pwr.OwnerUserId
LEFT JOIN DuplicatePosts dup ON pwr.Id = dup.PostId
WHERE ucs.TotalQuestions + ucs.TotalAnswers > 0
  AND (
      pwr.Score > 10
      OR (pwr.CommentsCount > 5 AND pwr.PostStatus = 'Open')
  )
ORDER BY ucs.Reputation DESC, pwr.Score DESC NULLS LAST, tb.BadgeClass, tb.BadgeDate DESC
LIMIT 100;