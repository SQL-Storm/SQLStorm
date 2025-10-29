WITH QuestionActivity AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS QuestionCreationDate,
        p.ViewCount AS QuestionViewCount,
        p.Score AS QuestionScore,
        p.AnswerCount AS QuestionAnswerCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        p.LastActivityDate AS QuestionLastActivityDate,
        COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnQuestion,
        ROW_NUMBER() OVER(ORDER BY p.CreationDate DESC, p.Id) AS RowNum
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        p.LastActivityDate
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.CommentCount AS AnswerCommentCount,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
UserEngagement AS (
    SELECT
        qa.OwnerUserId,
        COUNT(DISTINCT qa.QuestionId) AS QuestionsAsked,
        SUM(qa.QuestionScore) AS TotalQuestionScore,
        AVG(qa.QuestionViewCount) AS AvgQuestionViews,
        COUNT(DISTINCT ad.AnswerId) AS AnswersGiven,
        SUM(ad.AnswerScore) AS TotalAnswerScore,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        MAX(b.Date) AS LastBadgeDate
    FROM QuestionActivity qa
    LEFT JOIN AnswerDetails ad ON qa.QuestionId = ad.QuestionId
    LEFT JOIN Badges b ON qa.OwnerUserId = b.UserId
    GROUP BY qa.OwnerUserId
)
SELECT
    qa.QuestionTitle,
    qa.OwnerDisplayName AS QuestionOwner,
    qa.QuestionCreationDate,
    qa.QuestionViewCount,
    qa.QuestionScore,
    qa.QuestionAnswerCount,
    qa.QuestionFavoriteCount,
    qa.QuestionLastActivityDate,
    qa.CommentCountOnQuestion,
    qa.UpVotesOnQuestion,
    qa.DownVotesOnQuestion,
    ad.AnswerId,
    ad.OwnerDisplayName AS AnswerOwner,
    ad.AnswerCreationDate,
    ad.AnswerScore,
    ad.AnswerRank,
    COALESCE(ue.QuestionsAsked, 0) AS UserQuestionsAsked,
    COALESCE(ue.TotalQuestionScore, 0) AS UserTotalQuestionScore,
    COALESCE(ue.AvgQuestionViews, 0.0) AS UserAvgQuestionViews,
    COALESCE(ue.AnswersGiven, 0) AS UserAnswersGiven,
    COALESCE(ue.TotalAnswerScore, 0) AS UserTotalAnswerScore,
    COALESCE(ue.BadgesEarned, 0) AS UserBadgesEarned,
    ue.LastBadgeDate,
    CASE
        WHEN qa.QuestionScore > 100 THEN 'High Score'
        WHEN qa.QuestionAnswerCount > 50 THEN 'Popular'
        WHEN qa.QuestionViewCount > 10000 THEN 'Highly Viewed'
        WHEN qa.QuestionLastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days' THEN 'Active Recently'
        ELSE 'Standard'
    END AS QuestionCategory,
    SUBSTRING(qa.QuestionTitle FROM 1 FOR 50) AS ShortTitle,
    CHAR_LENGTH(qa.QuestionTitle) AS TitleLength,
    CAST(qa.QuestionScore AS DOUBLE PRECISION) / NULLIF(qa.QuestionViewCount, 0) AS ScoreToViewRatio,
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = qa.QuestionId AND c2.UserId IS NULL) AS AnonymousCommentsOnQuestion,
    CASE
        WHEN qa.OwnerUserId IS NULL THEN 'Community User'
        WHEN qa.OwnerDisplayName IS NULL THEN 'Anonymous Owner'
        ELSE qa.OwnerDisplayName
    END AS ResolvedOwnerName,
    CASE
        WHEN qa.QuestionFavoriteCount > 0 AND qa.QuestionScore > 0 THEN TRUE
        WHEN qa.QuestionFavoriteCount = 0 AND qa.QuestionScore <= 0 THEN FALSE
        ELSE NULL
    END AS IsPotentiallyValuable,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = qa.QuestionId AND pl.LinkTypeId = 3) THEN 'Linked as Duplicate'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = qa.QuestionId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of'
        ELSE 'Not Linked as Duplicate'
    END AS LinkStatus
FROM QuestionActivity qa
LEFT JOIN AnswerDetails ad ON qa.QuestionId = ad.QuestionId AND ad.AnswerRank = 1
LEFT JOIN UserEngagement ue ON qa.OwnerUserId = ue.OwnerUserId
WHERE qa.RowNum BETWEEN 1 AND 100
ORDER BY qa.QuestionCreationDate DESC;