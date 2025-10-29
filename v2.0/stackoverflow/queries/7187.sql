-- {"query": "7187.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1902}
WITH QuestionStats AS (
  SELECT 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    u.DisplayName AS OwnerDisplayName,
    CASE 
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
      ELSE 0 
    END AS HasAcceptedAnswer,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserQuestionNumber
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= TIMESTAMP '2020-01-01'
    AND p.ViewCount > 1000
),
AnswerStats AS (
  SELECT 
    a.ParentId AS QuestionId,
    COUNT(*) AS AnswerCount,
    SUM(a.Score) AS TotalAnswerScore,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.CreationDate) AS LatestAnswerDate
  FROM Posts a
  WHERE a.PostTypeId = 2 
    AND a.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY a.ParentId
),
TagAnalysis AS (
  SELECT 
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE 
      WHEN t.IsRequired = TRUE THEN 'Required' 
      WHEN t.IsModeratorOnly = TRUE THEN 'Moderator Only' 
      ELSE 'Regular' 
    END AS TagType
  FROM Tags t
  WHERE t.Count > 100
),
UserActivity AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    MAX(p.CreationDate) AS LastPostDate,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS AccountAgeDays,
    CASE 
      WHEN u.Reputation >= 10000 THEN 'Elite'
      WHEN u.Reputation >= 1000 THEN 'Expert'
      WHEN u.Reputation >= 100 THEN 'Intermediate'
      ELSE 'Beginner'
    END AS ReputationLevel
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.CreationDate
),
BountyData AS (
  SELECT 
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyStarted,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyClosed,
    COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount,
    COUNT(CASE WHEN v.VoteTypeId = 9 THEN 1 END) AS BountyCloseCount
  FROM Votes v
  WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
    AND v.VoteTypeId IN (8, 9)
  GROUP BY v.PostId
)
SELECT 
  qs.Id AS QuestionId,
  qs.Title,
  qs.Score,
  qs.ViewCount,
  qs.AnswerCount,
  qs.CommentCount,
  qs.HasAcceptedAnswer,
  qs.ScoreRank,
  qs.UserQuestionNumber,
  qs.OwnerDisplayName,
  COALESCE(ans.AnswerCount, 0) AS ActualAnswerCount,
  COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
  CASE 
    WHEN ans.LatestAnswerDate IS NOT NULL THEN CAST(EXTRACT(EPOCH FROM (ans.LatestAnswerDate - qs.CreationDate)) / 86400 AS INTEGER)
    ELSE NULL 
  END AS DaysToFirstAnswer,
  SUBSTRING(qs.Tags FROM 2 FOR (CHAR_LENGTH(qs.Tags) - 2)) AS RawTags,
  STRING_AGG(ta.TagName, ', ') AS QuestionTags,
  ud.TotalPosts,
  ud.Questions,
  ud.Answers,
  ud.ReputationLevel,
  COALESCE(bd.TotalBountyStarted, 0) AS TotalBountyStarted,
  COALESCE(bd.TotalBountyClosed, 0) AS TotalBountyClosed,
  CASE 
    WHEN qs.ViewCount > 0 THEN CAST((qs.Score * 1.0 / qs.ViewCount) AS NUMERIC(10,4))
    ELSE 0 
  END AS ScorePerView,
  CASE 
    WHEN qs.AnswerCount > 0 THEN CAST((qs.Score * 1.0 / qs.AnswerCount) AS NUMERIC(10,4))
    ELSE 0 
  END AS ScorePerAnswer,
  CASE 
    WHEN qs.CommentCount > 0 THEN CAST((qs.ViewCount * 1.0 / qs.CommentCount) AS NUMERIC(10,4))
    ELSE 0 
  END AS ViewsPerComment,
  CASE 
    WHEN qs.CommentCount > 0 AND qs.AnswerCount > 0 THEN CAST((qs.CommentCount * 1.0 / qs.AnswerCount) AS NUMERIC(10,4))
    ELSE 0 
  END AS CommentsPerAnswer,
  'QuestionRank' || CAST(qs.ScoreRank AS VARCHAR) AS QuestionRankLabel,
  CASE 
    WHEN qs.Score > 100 THEN 'Highly Ranked'
    WHEN qs.Score > 50 THEN 'Moderately Ranked'
    ELSE 'Low Ranked' 
  END AS ScoreCategory,
  COALESCE(ud.AccountAgeDays, 0) AS AccountAgeInDays,
  CASE 
    WHEN ud.AccountAgeDays > 365 THEN 'Long Term User'
    WHEN ud.AccountAgeDays > 180 THEN 'Regular User'
    ELSE 'New User' 
  END AS UserSeniority,
  CASE 
    WHEN COALESCE(bd.TotalBountyStarted, 0) > 0 THEN 'Bounty Active'
    WHEN COALESCE(bd.TotalBountyClosed, 0) > 0 THEN 'Bounty Closed'
    ELSE 'No Bounty' 
  END AS BountyStatus,
  COALESCE(ud.Reputation, 0) AS UserReputation,
  CASE 
    WHEN COALESCE(ud.Reputation, 0) >= 10000 THEN 1 
    WHEN COALESCE(ud.Reputation, 0) >= 1000 THEN 2 
    WHEN COALESCE(ud.Reputation, 0) >= 100 THEN 3 
    ELSE 4 
  END AS ReputationLevelOrdinal
FROM QuestionStats qs
LEFT JOIN AnswerStats ans ON qs.Id = ans.QuestionId
LEFT JOIN UserActivity ud ON qs.OwnerUserId = ud.UserId
LEFT JOIN BountyData bd ON qs.Id = bd.PostId
LEFT JOIN (
  SELECT 
    p.Id AS QuestionId,
    tag_parts.value AS TagName
  FROM Posts p,
  LATERAL (
    SELECT value FROM unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS value
  ) tag_parts
  WHERE p.PostTypeId = 1 AND p.CreationDate >= TIMESTAMP '2020-01-01'
) tag_mapping ON qs.Id = tag_mapping.QuestionId
LEFT JOIN TagAnalysis ta ON tag_mapping.TagName = ta.TagName
WHERE (COALESCE(ans.AnswerCount, 0) > 0 OR qs.HasAcceptedAnswer = 1)
  AND (qs.ViewCount >= 500 OR qs.Score >= 10)
  AND (ud.TotalPosts >= 1 OR ud.UserId IS NOT NULL)
  AND (
    COALESCE(bd.TotalBountyStarted, 0) > 0 
    OR COALESCE(bd.TotalBountyClosed, 0) > 0 
    OR bd.PostId IS NULL
  )
  AND EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.ParentId = qs.Id 
      AND p2.PostTypeId = 2 
      AND p2.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p2.ParentId
    HAVING COUNT(*) > 0
  )
GROUP BY
  qs.Id,
  qs.Title,
  qs.Score,
  qs.ViewCount,
  qs.AnswerCount,
  qs.CommentCount,
  qs.HasAcceptedAnswer,
  qs.ScoreRank,
  qs.UserQuestionNumber,
  qs.OwnerDisplayName,
  ans.AnswerCount,
  ans.TotalAnswerScore,
  ans.AvgAnswerScore,
  ans.LatestAnswerDate,
  qs.CreationDate,
  qs.Tags,
  ud.TotalPosts,
  ud.Questions,
  ud.Answers,
  ud.ReputationLevel,
  bd.TotalBountyStarted,
  bd.TotalBountyClosed,
  ud.AccountAgeDays,
  ud.Reputation,
  qs.ScoreRank,
  ta.TagName
ORDER BY qs.ScoreRank, qs.ViewCount DESC, qs.CreationDate DESC;