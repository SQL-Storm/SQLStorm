-- {"query": "4238.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1702} 

WITH RankedUserEdits AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserFavoritePosts AS (
    SELECT
        v.UserId,
        v.PostId,
        v.CreationDate AS FavoriteDate
    FROM Votes v
    WHERE v.VoteTypeId = 5 -- Favorite
),
PostScoreEvolution AS (
    SELECT
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        p.Score - LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS ScoreDelta
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
),
UserQuestionMetrics AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswerCountOnQuestions,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS MaxQuestionViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    p.Id AS QuestionId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    p.CreationDate AS QuestionCreationDate,
    p.Score AS QuestionScore,
    p.AnswerCount AS QuestionAnswerCount,
    p.ViewCount AS QuestionViewCount,
    uqm.QuestionCount AS UserTotalQuestions,
    uqm.AvgQuestionScore AS UserAvgQuestionScore,
    uqm.TotalAnswerCountOnQuestions AS UserTotalAnswersOnHisQuestions,
    COALESCE(ca.CommentCount, 0) AS TotalCommentsOnQuestion,
    COALESCE(ca.PositiveCommentCount, 0) AS PositiveCommentsOnQuestion,
    COALESCE(ca.AvgCommentScore, 0.0) AS AvgCommentScoreOnQuestion,
    pse.ScoreDelta AS QuestionScoreDeltaSinceLastRecord,
    rue.EditDate AS LatestEditDateByOwner,
    upf.FavoriteDate AS FavoritedDateBySomeone,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    lt.Name AS DuplicateLinkType
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserQuestionMetrics uqm ON u.Id = uqm.UserId
LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
LEFT JOIN PostScoreEvolution pse ON p.Id = pse.PostId AND p.CreationDate = pse.CreationDate
LEFT JOIN RankedUserEdits rue ON p.Id = rue.PostId AND rue.rn = 1
LEFT JOIN UserFavoritePosts upf ON p.Id = upf.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3 -- Duplicate link type
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE p.PostTypeId = 1 -- Only consider questions
  AND p.Score > 10
  AND u.Reputation > 1000
  AND pse.ScoreDelta > 0
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND LENGTH(c.Text) > 100)
  AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19 /* Question Protected */)
UNION ALL
SELECT
    p.Id AS QuestionId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    p.CreationDate AS QuestionCreationDate,
    p.Score AS QuestionScore,
    p.AnswerCount AS QuestionAnswerCount,
    p.ViewCount AS QuestionViewCount,
    uqm.QuestionCount AS UserTotalQuestions,
    uqm.AvgQuestionScore AS UserAvgQuestionScore,
    uqm.TotalAnswerCountOnQuestions AS UserTotalAnswersOnHisQuestions,
    COALESCE(ca.CommentCount, 0) AS TotalCommentsOnQuestion,
    COALESCE(ca.PositiveCommentCount, 0) AS PositiveCommentsOnQuestion,
    COALESCE(ca.AvgCommentScore, 0.0) AS AvgCommentScoreOnQuestion,
    pse.ScoreDelta AS QuestionScoreDeltaSinceLastRecord,
    rue.EditDate AS LatestEditDateByOwner,
    upf.FavoriteDate AS FavoritedDateBySomeone,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    lt.Name AS DuplicateLinkType
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserQuestionMetrics uqm ON u.Id = uqm.UserId
LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
LEFT JOIN PostScoreEvolution pse ON p.Id = pse.PostId AND p.CreationDate = pse.CreationDate
LEFT JOIN RankedUserEdits rue ON p.Id = rue.PostId AND rue.rn = 1
LEFT JOIN UserFavoritePosts upf ON p.Id = upf.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.RelatedPostId AND pl.LinkTypeId = 3 -- Where this question is a duplicate of another
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE p.PostTypeId = 1 -- Only consider questions
  AND p.Score > 10
  AND u.Reputation > 1000
  AND pse.ScoreDelta < 0
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND NOT EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND LENGTH(c.Text) > 100)
  AND NOT EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19 /* Question Protected */);
