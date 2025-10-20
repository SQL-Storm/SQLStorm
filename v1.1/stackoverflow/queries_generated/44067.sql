-- {"query": "44067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 153698, "output_tokens": 52884} 

WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Score,
    p.ViewCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
    CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
    CASE WHEN p.ParentId IS NOT NULL THEN 1 ELSE 0 END AS IsAnswer,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(u.UpVotes, 0) AS OwnerUpVotes,
    COALESCE(u.DownVotes, 0) AS OwnerDownVotes,
    COALESCE(u.Views, 0) AS OwnerViews,
    CASE WHEN p.PostTypeId = 1 THEN CHAR_LENGTH(p.Title) ELSE NULL END AS QuestionTitleLength,
    CASE WHEN p.PostTypeId = 1 THEN LENGTH(p.Tags) ELSE NULL END AS QuestionTagLength,
    CASE WHEN p.PostTypeId = 1 THEN LENGTH(p.Body) ELSE NULL END AS QuestionBodyLength,
    CASE WHEN p.PostTypeId = 2 THEN LENGTH(p.Body) ELSE NULL END AS AnswerBodyLength
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT 
  ROUND(AVG(QuestionTitleLength), 2) AS AvgQuestionTitleLength,
  ROUND(AVG(QuestionTagLength), 2) AS AvgQuestionTagLength,
  ROUND(AVG(QuestionBodyLength), 2) AS AvgQuestionBodyLength,
  ROUND(AVG(AnswerBodyLength), 2) AS AvgAnswerBodyLength,
  ROUND(AVG(Score), 2) AS AvgScore,
  ROUND(AVG(ViewCount), 2) AS AvgViewCount,
  ROUND(AVG(AnswerCount), 2) AS AvgAnswerCount,
  ROUND(AVG(CommentCount), 2) AS AvgCommentCount,
  ROUND(AVG(FavoriteCount), 2) AS AvgFavoriteCount,
  ROUND(AVG(OwnerReputation), 2) AS AvgOwnerReputation,
  ROUND(AVG(OwnerUpVotes), 2) AS AvgOwnerUpVotes,
  ROUND(AVG(OwnerDownVotes), 2) AS AvgOwnerDownVotes,
  ROUND(AVG(OwnerViews), 2) AS AvgOwnerViews,
  ROUND(SUM(CASE WHEN IsClosed = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS PercentageClosed,
  ROUND(SUM(CASE WHEN IsCommunityOwned = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS PercentageCommunityOwned,
  ROUND(SUM(CASE WHEN HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS PercentageWithAcceptedAnswer,
  ROUND(SUM(CASE WHEN IsAnswer = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS PercentageAnswers
FROM cte;
