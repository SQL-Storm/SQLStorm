-- {"query": "4253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1634} 

WITH
  RankedUserVotes AS (
    SELECT
      v.UserId,
      v.PostId,
      v.VoteTypeId,
      v.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS VoteRank
    FROM Votes AS v
    WHERE
      v.VoteTypeId IN (2, 3)
  ),
  UserVoteSummary AS (
    SELECT
      UserId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVoteCount,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVoteCount,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVoteScore
    FROM RankedUserVotes
    WHERE
      VoteRank <= 100
    GROUP BY
      UserId
  ),
  PostHistoryAndScores AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS TitleEdits,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
      MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
      p.OwnerUserId,
      p.Score AS PostScore,
      p.ViewCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      pt.Name AS PostTypeName,
      COALESCE(p.AnswerCount, 0) AS AnswerCount
    FROM PostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate >= '2023-01-01'
    GROUP BY
      ph.PostId,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.LastActivityDate,
      pt.Name,
      p.AnswerCount
  )
SELECT
  'User Analysis' AS AnalysisType,
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  COALESCE(uvs.UpVoteCount, 0) AS TotalUpVotesGiven,
  COALESCE(uvs.DownVoteCount, 0) AS TotalDownVotesGiven,
  COALESCE(uvs.NetVoteScore, 0) AS NetVoteScoreGiven,
  COUNT(DISTINCT phs.PostId) AS PostsEditedByThisUser,
  SUM(phs.BodyEdits) AS TotalBodyEdits,
  SUM(phs.TitleEdits) AS TotalTitleEdits,
  AVG(CASE WHEN phs.PostTypeName = 'Question' THEN phs.PostScore ELSE NULL END) AS AvgQuestionScore,
  AVG(CASE WHEN phs.PostTypeName = 'Answer' THEN phs.PostScore ELSE NULL END) AS AvgAnswerScore,
  AVG(phs.ViewCount) AS AvgPostViewCount,
  AVG(phs.CommentCount) AS AvgPostCommentCount,
  AVG(phs.FavoriteCount) AS AvgPostFavoriteCount,
  COUNT(DISTINCTCASE WHEN phs.PostTypeName = 'Question' THEN phs.PostId ELSE NULL END) AS QuestionsPosted,
  COUNT(DISTINCTCASE WHEN phs.PostTypeName = 'Answer' THEN phs.PostId ELSE NULL END) AS AnswersPosted,
  AVG(CASE WHEN phs.PostTypeName = 'Question' THEN DATEDIFF(day, phs.PostCreationDate, phs.LastActivityDate) ELSE NULL END) AS AvgDaysActiveForQuestions,
  MAX(u.Views) AS UserViews,
  COUNT(b.Id) AS TotalBadgesEarned,
  MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LastGoldBadgeDate,
  MAX(CASE WHEN b.Class = 2 THEN b.Date ELSE NULL END) AS LastSilverBadgeDate,
  MAX(CASE WHEN b.Class = 3 THEN b.Date ELSE NULL END) AS LastBronzeBadgeDate,
  COUNT(DISTINCT CASE WHEN phs.LastClosedDate IS NOT NULL THEN phs.PostId ELSE NULL END) AS PostsClosed,
  COUNT(DISTINCT CASE WHEN phs.LastReopenedDate IS NOT NULL THEN phs.PostId ELSE NULL END) AS PostsReopened,
  SUM(phs.AnswerCount) AS TotalAnswersOnUserPosts,
  LOG(ABS(u.Reputation) + 1) AS LogReputation,
  CASE
    WHEN u.EmailHash IS NOT NULL THEN 'Has Email Hash'
    ELSE 'No Email Hash'
  END AS EmailStatus,
  IIF(
    u.WebsiteUrl LIKE '%stackoverflow.com%',
    'Stack Overflow Profile',
    'Other/No Website'
  ) AS WebsiteCategory,
  DATEDIFF(
    day,
    u.CreationDate,
    GETDATE()
  ) AS UserAgeInDays,
  CASE
    WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
    WHEN CHARINDEX(',', u.Location) > 0 THEN SUBSTRING(u.Location, 1, CHARINDEX(',', u.Location) - 1)
    ELSE u.Location
  END AS PrimaryLocation,
  CASE
    WHEN u.AboutMe LIKE '%[data-type="mention"]%' THEN 'Contains Mentions'
    ELSE 'No Mentions'
  END AS AboutMeContent
FROM Users AS u
LEFT JOIN UserVoteSummary AS uvs
  ON u.Id = uvs.UserId
LEFT JOIN PostHistoryAndScores AS phs
  ON u.Id = phs.OwnerUserId
LEFT JOIN Badges AS b
  ON u.Id = b.UserId
WHERE
  u.Id % 10 = 0 -- Sample a subset of users for performance
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  uvs.UpVoteCount,
  uvs.DownVoteCount,
  uvs.NetVoteScore,
  u.Views,
  u.EmailHash,
  u.WebsiteUrl,
  u.Location,
  u.AboutMe
HAVING
  COUNT(DISTINCT phs.PostId) > 5 OR uvs.NetVoteScore > 100 -- Filter for users with significant activity or voting
ORDER BY
  u.Reputation DESC,
  UserAgeInDays DESC
LIMIT 1000;
