WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
        MAX(p.ViewCount) AS MaxQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS RecentAnswerCount,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
    GROUP BY a.ParentId
),
ComplexPostData AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(p.Title, 'N/A') AS Title,
        CASE WHEN p.PostTypeId = 1 THEN p.Tags ELSE NULL END AS QuestionTags,
        LENGTH(p.Body) AS BodyLength,
        REPLACE(p.Body, '<p>', '') AS CleanedBody,
        ph.Comment AS LatestHistoryComment,
        ph.CreationDate AS LatestHistoryDate,
        ph.PostHistoryTypeId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, Comment, CreationDate, PostHistoryTypeId, ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) as rn
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,19,20,35,36)
    ) ph ON p.Id = ph.PostId AND ph.rn = 1
    WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
AggregatedAnswers AS (
    SELECT
        p.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerCreationDate
    FROM Posts p
    JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    rq.QuestionCreationDate,
    rq.QuestionScore,
    ue.DisplayName AS OwnerDisplayName,
    ue.Reputation AS OwnerReputation,
    ue.TotalQuestions AS OwnerTotalQuestions,
    ue.PositiveScoreQuestions AS OwnerPositiveScoreQuestions,
    ue.AvgAnswersPerQuestion AS OwnerAvgAnswersPerQuestion,
    ue.MaxQuestionViews AS OwnerMaxQuestionViews,
    aa.TotalAnswers,
    aa.TotalAnswerScore,
    aa.AvgAnswerScore,
    aa.LatestAnswerCreationDate,
    ra.RecentAnswerCount,
    ra.LatestAnswerDate AS MostRecentAnswerDate,
    cpd.PostTypeName,
    cpd.Score AS PostScore,
    cpd.ViewCount AS PostViewCount,
    cpd.FavoriteCount AS PostFavoriteCount,
    cpd.CommentCount AS PostCommentCount,
    cpd.ClosedDate,
    cpd.CommunityOwnedDate,
    cpd.QuestionTags,
    cpd.BodyLength,
    cpd.CleanedBody,
    cpd.LatestHistoryComment,
    cpd.LatestHistoryDate,
    cpd.PostHistoryTypeId,
    CASE WHEN cpd.ClosedDate IS NOT NULL THEN 'Closed' WHEN cpd.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'Open' END AS PostStatus,
    (cpd.Score * 1.0 / NULLIF(cpd.ViewCount, 0)) AS ScoreToViewRatio,
    SUBSTRING(
      cpd.QuestionTags FROM
      (POSITION('><' IN cpd.QuestionTags) + 2) FOR
      (POSITION('><' IN SUBSTRING(cpd.QuestionTags FROM POSITION('><' IN cpd.QuestionTags) + 2)) - 1)
    ) AS SecondTag,
    CASE WHEN ue.UserCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years') THEN 'Veteran' WHEN ue.UserCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'Established' ELSE 'New' END AS UserTenure,
    CASE WHEN cpda.PostTypeId IS NOT NULL THEN 'Has Answers' ELSE 'No Answers' END AS HasAnswers,
    CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3) THEN 'Is Linked As Duplicate' ELSE 'Not Linked As Duplicate' END AS DuplicateLinkStatus
FROM RankedQuestions rq
JOIN UserEngagement ue ON rq.OwnerUserId = ue.UserId
LEFT JOIN AggregatedAnswers aa ON rq.QuestionId = aa.QuestionId
LEFT JOIN RecentAnswers ra ON rq.QuestionId = ra.QuestionId
LEFT JOIN ComplexPostData cpd ON rq.QuestionId = cpd.PostId
LEFT JOIN Posts cpda ON cpd.PostId = cpda.ParentId AND cpda.PostTypeId = 2
WHERE rq.RowNum <= 5
ORDER BY rq.QuestionScore DESC, rq.QuestionCreationDate DESC;