-- {"query": "4517.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1916} 

WITH
  PostScores AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.PostTypeId,
      p.CreationDate,
      p.ClosedDate,
      p.CommunityOwnedDate,
      pt.Name AS PostTypeName,
      COALESCE(
        (
          SELECT
            SUM(v.VoteTypeId = 2) -- UpMod
          FROM
            Votes AS v
          WHERE
            v.PostId = p.Id
        ),
        0
      ) AS UpVotes,
      COALESCE(
        (
          SELECT
            SUM(v.VoteTypeId = 3) -- DownMod
          FROM
            Votes AS v
          WHERE
            v.PostId = p.Id
        ),
        0
      ) AS DownVotes,
      COALESCE(
        (
          SELECT
            COUNT(c.Id)
          FROM
            Comments AS c
          WHERE
            c.PostId = p.Id
        ),
        0
      ) AS CommentCountActual,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserScoreRank,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByPostType,
      (
        CASE
          WHEN p.ClosedDate IS NOT NULL THEN 1
          ELSE 0
        END
      ) AS IsClosed,
      (
        CASE
          WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
          ELSE 0
        END
      ) AS IsCommunityOwned
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(ps.Score) AS AvgPostScore,
      MAX(ps.CreationDate) AS LastPostCreationDate
    FROM
      Users AS u
      LEFT JOIN PostScores AS ps
        ON u.Id = ps.OwnerUserId
      LEFT JOIN PostHistory AS ph
        ON u.Id = ph.UserId
      LEFT JOIN Badges AS b
        ON u.Id = b.UserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate
  ),
  TopQuestions AS (
    SELECT
      ps.PostId,
      ps.OwnerUserId,
      ps.Title,
      ps.Score,
      ps.ViewCount,
      ps.UpVotes,
      ps.DownVotes,
      ps.AnswerCount AS ActualAnswerCount,
      ps.CommentCountActual,
      ps.IsClosed,
      ps.IsCommunityOwned,
      DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
      LAG(ps.Score, 1, 0) OVER (ORDER BY ps.CreationDate) AS PreviousPostScore
    FROM
      PostScores AS ps
    WHERE
      ps.PostTypeId = 1 -- Question
      AND ps.Score > 10 -- Filter for reasonably scored questions
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      pl.RelatedPostId,
      lt.Name AS LinkType,
      CASE
        WHEN lt.Name = 'Duplicate' THEN 1
        ELSE 0
      END AS IsDuplicateLink,
      CASE
        WHEN lt.Name = 'Linked' THEN 1
        ELSE 0
      END AS IsLinkedLink
    FROM
      PostLinks AS pl
      JOIN LinkTypes AS lt
        ON pl.LinkTypeId = lt.Id
  )
SELECT
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.LastAccessDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.BadgeCount,
  ua.PostHistoryCount,
  COALESCE(ua.AvgPostScore, 0) AS UserAvgPostScore,
  ps.Score AS PostScore,
  ps.ViewCount AS PostViewCount,
  ps.UpVotes AS PostUpVotes,
  ps.DownVotes AS PostDownVotes,
  ps.CommentCountActual AS PostCommentCount,
  ps.AnswerCount AS PostAnswerCount,
  ps.IsClosed,
  ps.IsCommunityOwned,
  tq.ScoreRank AS QuestionScoreRank,
  tq.PreviousPostScore AS ScoreOfPreviousQuestionByDate,
  COUNT(pl.PostId) OVER (PARTITION BY ps.PostId) AS NumberOfLinksToThisPost,
  SUM(pla.IsDuplicateLink) OVER (PARTITION BY ps.PostId) AS DuplicateLinksToThisPost,
  SUM(pla.IsLinkedLink) OVER (PARTITION BY ps.PostId) AS LinkedLinksToThisPost,
  CASE
    WHEN ps.PostTypeName = 'Question'
    AND ps.ClosedDate IS NULL
    AND ps.CommunityOwnedDate IS NULL
    AND ps.Score > 50 THEN 'HighValueQuestion'
    WHEN ps.PostTypeName = 'Answer'
    AND ps.Score > 20 THEN 'HighValueAnswer'
    ELSE 'Other'
  END AS PostValueCategory,
  ABS(ps.Score - ps.AvgScoreByPostType) AS ScoreDifferenceFromAvg,
  UPPER(SUBSTRING(ua.DisplayName FROM 1 FOR 1)) AS FirstLetterOfDisplayName,
  CASE
    WHEN ua.LastAccessDate < ua.UserCreationDate + INTERVAL '3 months' THEN 'EarlyAdopter'
    WHEN ua.LastAccessDate > ua.UserCreationDate + INTERVAL '5 years' THEN 'LongTermUser'
    ELSE 'RegularUser'
  END AS UserTenureCategory,
  COALESCE(ps.OwnerUserId, -1) AS SafeOwnerUserId
FROM
  UserActivity AS ua
JOIN PostScores AS ps
  ON ua.UserId = ps.OwnerUserId
LEFT JOIN TopQuestions AS tq
  ON ps.PostId = tq.PostId
LEFT JOIN PostLinkAnalysis AS pla
  ON ps.PostId = pla.RelatedPostId -- Analyze links pointing TO the post
WHERE
  ps.Score > 0
  AND ua.Reputation > 1000
  AND ps.PostTypeName IN ('Question', 'Answer')
  AND ps.CreationDate >= '2023-01-01'
  AND ps.Score < 1000
  AND ua.DisplayName IS NOT NULL
  AND ua.DisplayName <> ''
  AND ua.DisplayName <> 'Community' -- Exclude community user display name if it exists
GROUP BY
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.LastAccessDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.BadgeCount,
  ua.PostHistoryCount,
  ua.AvgPostScore,
  ps.Score,
  ps.ViewCount,
  ps.UpVotes,
  ps.DownVotes,
  ps.CommentCountActual,
  ps.AnswerCount,
  ps.IsClosed,
  ps.IsCommunityOwned,
  tq.ScoreRank,
  tq.PreviousPostScore,
  ps.PostId,
  ps.PostTypeName,
  ps.ClosedDate,
  ps.CommunityOwnedDate,
  ps.Score,
  ps.AvgScoreByPostType,
  ps.OwnerUserId
HAVING
  COUNT(pla.PostId) <= 5; -- Limit posts with an excessive number of incoming links
