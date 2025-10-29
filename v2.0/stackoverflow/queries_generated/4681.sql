-- {"query": "4681.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1498} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryAction,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostEngagement AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      AVG(p.Score) AS AverageScore
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  TagSpecificUserActivity AS (
    SELECT
      p.OwnerUserId,
      t.TagName,
      COUNT(DISTINCT p.Id) AS TagPostCount,
      SUM(p.Score) AS TagScoreSum,
      CASE
        WHEN t.IsModeratorOnly = 1 THEN 'ModeratorOnly'
        WHEN t.IsRequired = 1 THEN 'Required'
        ELSE 'Standard'
      END AS TagType
    FROM Posts AS p
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '') AS ts -- Assuming STRING_SPLIT is available for tag parsing
    JOIN Tags AS t
      ON ts.value = t.TagName
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId,
      t.TagName,
      t.IsModeratorOnly,
      t.IsRequired
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      vt.Name AS VoteType,
      COUNT(v.Id) AS VoteCount,
      SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
      AND vt.Id IN (2, 3, 8) -- UpMod, DownMod, BountyStart
    GROUP BY
      v.UserId,
      vt.Name
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(t.QuestionCount, 0) AS TotalQuestionsPosted,
  COALESCE(t.AnswerCount, 0) AS TotalAnswersPosted,
  COALESCE(t.AcceptedAnswerCount, 0) AS AcceptedAnswers,
  COALESCE(t.AverageScore, 0.0) AS AvgPostScore,
  COALESCE(rpe.CreationDate, '1900-01-01') AS LastEditDateForPost,
  COALESCE(rpe.HistoryAction, 'NoEdits') AS LastEditAction,
  tsu.TagName,
  COALESCE(tsu.TagPostCount, 0) AS TagSpecificPosts,
  COALESCE(tsu.TagScoreSum, 0) AS TagSpecificScore,
  tsu.TagType,
  COALESCE(uvs_up.VoteCount, 0) AS TotalUpVotesReceived,
  COALESCE(uvs_down.VoteCount, 0) AS TotalDownVotesReceived,
  COALESCE(uvs_bounty.TotalBountyAmount, 0) AS TotalBountyGiven,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'StackOverflow User'
    WHEN u.Location IS NOT NULL AND u.Location LIKE '%United States%' THEN 'US Based'
    ELSE 'Other'
  END AS UserClassification,
  CASE
    WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'No Bio'
    WHEN LENGTH(u.AboutMe) < 50 THEN 'Short Bio'
    ELSE 'Detailed Bio'
  END AS BioLengthCategory,
  COUNT(DISTINCT c.Id) AS CommentCountOnUserPosts,
  CASE
    WHEN u.CreationDate BETWEEN DATE_SUB(NOW(), INTERVAL 1 YEAR) AND NOW() THEN 'Recent'
    ELSE 'Established'
  END AS UserAccountAge
FROM Users AS u
LEFT JOIN UserPostEngagement AS t
  ON u.Id = t.OwnerUserId
LEFT JOIN RankedPostEdits AS rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
LEFT JOIN TagSpecificUserActivity AS tsu
  ON u.Id = tsu.OwnerUserId
LEFT JOIN UserVoteSummary AS uvs_up
  ON u.Id = uvs_up.UserId AND uvs_up.VoteType = 'UpMod'
LEFT JOIN UserVoteSummary AS uvs_down
  ON u.Id = uvs_down.UserId AND uvs_down.VoteType = 'DownMod'
LEFT JOIN UserVoteSummary AS uvs_bounty
  ON u.Id = uvs_bounty.UserId AND uvs_bounty.VoteType = 'BountyStart'
LEFT JOIN Posts AS p_for_comments
  ON u.Id = p_for_comments.OwnerUserId
LEFT JOIN Comments AS c
  ON p_for_comments.Id = c.PostId
WHERE
  u.Reputation > 100 -- Only consider users with some reputation
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  t.QuestionCount,
  t.AnswerCount,
  t.AcceptedAnswerCount,
  t.AverageScore,
  rpe.CreationDate,
  rpe.HistoryAction,
  tsu.TagName,
  tsu.TagPostCount,
  tsu.TagScoreSum,
  tsu.TagType,
  uvs_up.VoteCount,
  uvs_down.VoteCount,
  uvs_bounty.TotalBountyAmount,
  UserClassification,
  BioLengthCategory,
  UserAccountAge
ORDER BY
  u.Reputation DESC,
  u.CreationDate ASC;
