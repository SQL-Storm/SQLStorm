-- {"query": "18044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1636} 

WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score_desc,
    SUM(COALESCE(c.Score, 0)) OVER (PARTITION BY p.Id) AS TotalCommentScore,
    AVG(COALESCE(v.VoteTypeId, 0)) OVER (PARTITION BY p.Id) AS AvgVoteType,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
  FROM Posts AS p
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users AS u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) /* UpMod, DownMod */
  WHERE
    p.PostTypeId IN (1, 2) /* Questions and Answers */
  GROUP BY
    p.Id,
    p.PostTypeId,
    pt.Name,
    p.OwnerUserId,
    u.DisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate
), RecentQuestions AS (
  SELECT
    PostId,
    PostTypeName,
    OwnerUserId,
    OwnerDisplayName,
    PostCreationDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    TotalCommentScore,
    AvgVoteType,
    IsClosed,
    IsCommunityOwned,
    CASE
      WHEN DATEDIFF(day, PostCreationDate, GETDATE()) < 7 THEN 'Recent'
      WHEN DATEDIFF(day, PostCreationDate, GETDATE()) < 30 THEN 'Young'
      ELSE 'Mature'
    END AS PostAgeCategory
  FROM RankedPosts
  WHERE
    PostTypeId = 1 AND rn_desc <= 1000
), TopAnswers AS (
  SELECT
    PostId,
    OwnerUserId,
    OwnerDisplayName,
    PostCreationDate,
    Score,
    TotalCommentScore,
    AvgVoteType,
    CASE
      WHEN Score > 50 THEN 'Highly Rated'
      WHEN Score > 10 THEN 'Well Rated'
      ELSE 'Standard'
    END AS AnswerRating
  FROM RankedPosts
  WHERE
    PostTypeId = 2 AND rn_score_desc <= 500
), QuestionAnswerSummary AS (
  SELECT
    rq.PostId AS QuestionId,
    rq.PostTypeName AS QuestionType,
    rq.OwnerDisplayName AS QuestionOwner,
    rq.PostCreationDate AS QuestionCreationDate,
    rq.Score AS QuestionScore,
    rq.ViewCount AS QuestionViewCount,
    rq.AnswerCount AS QuestionAnswerCount,
    rq.FavoriteCount AS QuestionFavoriteCount,
    rq.TotalCommentScore AS QuestionTotalCommentScore,
    rq.AvgVoteType AS QuestionAvgVoteType,
    rq.IsClosed AS QuestionIsClosed,
    rq.IsCommunityOwned AS QuestionIsCommunityOwned,
    rq.PostAgeCategory,
    COUNT(ta.PostId) AS NumberOfTopAnswers,
    SUM(ta.Score) AS TotalScoreOfTopAnswers,
    MAX(ta.Score) AS MaxScoreOfTopAnswer,
    STRING_AGG(ta.AnswerRating, ', ') AS AnswerRatingDistribution
  FROM RecentQuestions AS rq
  LEFT JOIN TopAnswers AS ta
    ON rq.PostId = (
      SELECT
        ParentId
      FROM Posts
      WHERE
        Id = ta.PostId
    )
  GROUP BY
    rq.PostId,
    rq.PostTypeName,
    rq.OwnerDisplayName,
    rq.PostCreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.TotalCommentScore,
    rq.AvgVoteType,
    rq.IsClosed,
    rq.IsCommunityOwned,
    rq.PostAgeCategory
)
SELECT
  qas.QuestionId,
  qas.QuestionType,
  qas.QuestionOwner,
  qas.QuestionCreationDate,
  qas.QuestionScore,
  qas.QuestionViewCount,
  qas.QuestionAnswerCount,
  qas.QuestionFavoriteCount,
  qas.QuestionTotalCommentScore,
  qas.QuestionAvgVoteType,
  qas.QuestionIsClosed,
  qas.QuestionIsCommunityOwned,
  qas.PostAgeCategory,
  qas.NumberOfTopAnswers,
  qas.TotalScoreOfTopAnswers,
  qas.MaxScoreOfTopAnswer,
  qas.AnswerRatingDistribution,
  CASE
    WHEN qas.NumberOfTopAnswers > 0 THEN CAST(qas.TotalScoreOfTopAnswers AS REAL) / qas.NumberOfTopAnswers
    ELSE 0
  END AS AvgScoreOfTopAnswers,
  UPPER(SUBSTRING(COALESCE(qas.QuestionOwner, 'ANONYMOUS'), 1, 3)) AS OwnerInitials,
  IIF(qas.QuestionScore > 0, 'Positive', IIF(qas.QuestionScore < 0, 'Negative', 'Zero')) AS ScoreSentiment,
  COALESCE(pht.CommentCount, 0) AS PostHistoryEdits,
  CASE
    WHEN qas.QuestionIsClosed = 1 AND qas.QuestionCreationDate < DATEADD(year, -1, GETDATE()) THEN 'Old Closed Question'
    WHEN qas.QuestionIsClosed = 0 AND qas.QuestionScore > 100 THEN 'High Score Open Question'
    ELSE 'Standard Question'
  END AS QuestionStatus
FROM QuestionAnswerSummary AS qas
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS CommentCount
  FROM PostHistory
  WHERE
    PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  GROUP BY
    PostId
) AS pht
  ON qas.QuestionId = pht.PostId
WHERE
  qas.QuestionScore > -10
ORDER BY
  qas.QuestionCreationDate DESC
LIMIT 100;
