-- {"query": "5334.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1038} 
WITH user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate DESC) AS rn
  FROM Users u
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostTypeName
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_relations AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
),
hot_score AS (
  SELECT
    UP.Id AS UserId,
    UP.DisplayName,
    UP.Reputation,
    COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionCount,
    SUM(P.Score) AS TotalScore,
    AVG(P.Score) AS AvgScore,
    SUM(P.ViewCount) AS TotalViews,
    MAX(P.LastActivityDate) AS LastActivity
  FROM Users UP
  LEFT JOIN Posts P ON P.OwnerUserId = UP.Id
    AND P.LastActivityDate >= NOW() - INTERVAL '90 days'
  GROUP BY UP.Id, UP.DisplayName, UP.Reputation
),
correlated_comments AS (
  SELECT
    C.PostId,
    COUNT(*) AS CommentCount,
    STRING_AGG(C.Text, ' || ') AS AllComments
  FROM Comments C
  GROUP BY C.PostId
),
complex_view AS (
  SELECT
    RPN.PostId,
    RPN.OwnerUserId,
    RPN.PostTypeId,
    RPN.Title,
    RPN.Tags,
    RPN.CreationDate,
    RPN.LastActivityDate,
    RPN.Score,
    RPN.ViewCount,
    RPN.FavoriteCount,
    RPN.AnswerCount,
    RPN.CommentCount,
    RPN.ParentId,
    RPN.AcceptedAnswerId,
    RPN.Body,
    RPN.LastEditorUserId,
    RPN.LastEditDate,
    RPN.ContentLicense,
    HP.TotalScore AS PostHistoryScore,
    CC.CommentCount AS CommentCountImproved,
    CC.AllComments
  FROM recent_posts RPN
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS TotalScore
    FROM Votes
    GROUP BY PostId
  ) HP ON HP.PostId = RPN.PostId
  LEFT JOIN correlated_comments CC ON CC.PostId = RPN.PostId
  WHERE (RPN.Score > 0 OR RPN.ViewCount > 100) AND RPN.LastActivityDate > NOW() - INTERVAL '60 days'
)
SELECT
  U.UserId,
  U.DisplayName AS UserDisplayName,
  U.Reputation,
  U.CreationDate AS UserCreationDate,
  U.LastAccessDate,
  U.Location,
  U.AboutMe,
  U.Views,
  U.UpVotes,
  U.DownVotes,
  U.ProfileImageUrl,
  U.EmailHash,
  U.AccountId,
  P.PostId,
  P.PostTypeId,
  P.Title,
  P.Tags,
  P.CreationDate AS PostCreationDate,
  P.LastActivityDate AS PostLastActivityDate,
  P.Score,
  P.ViewCount,
  P.FavoriteCount,
  P.AnswerCount,
  P.CommentCount,
  P.ParentId,
  P.AcceptedAnswerId,
  P.Body,
  P.LastEditorUserId,
  P.LastEditDate,
  P.ContentLicense,
  P.PostTypeName,
  HC.TotalScore AS PostHistoryScore,
  CC.CommentCountImproved,
  CC.AllComments,
  HS.LastActivity
FROM complex_view HS
JOIN user_activity U ON U.Id = HS.OwnerUserId
JOIN Posts P ON P.Id = HS.PostId
LEFT JOIN hot_score HS2 ON HS2.UserId = U.Id
ORDER BY U.Reputation DESC, P.LastActivityDate DESC
LIMIT 500;