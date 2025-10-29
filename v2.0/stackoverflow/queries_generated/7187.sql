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
    u.DisplayName as OwnerDisplayName,
    CASE 
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
      ELSE 0 
    END as HasAcceptedAnswer,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserQuestionNumber
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2020-01-01'
    AND p.ViewCount > 1000
),
AnswerStats AS (
  SELECT 
    a.ParentId as QuestionId,
    COUNT(*) as AnswerCount,
    SUM(a.Score) as TotalAnswerScore,
    AVG(a.Score) as AvgAnswerScore,
    MAX(a.CreationDate) as LatestAnswerDate
  FROM Posts a
  WHERE a.PostTypeId = 2 
    AND a.CreationDate >= '2020-01-01'
  GROUP BY a.ParentId
),
TagAnalysis AS (
  SELECT 
    t.TagName,
    t.Count as TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE 
      WHEN t.IsRequired = 1 THEN 'Required' 
      WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' 
      ELSE 'Regular' 
    END as TagType
  FROM Tags t
  WHERE t.Count > 100
),
UserActivity AS (
  SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    MAX(p.CreationDate) as LastPostDate,
    DATEDIFF(DAY, u.CreationDate, GETDATE()) as AccountAgeDays,
    CASE 
      WHEN u.Reputation >= 10000 THEN 'Elite'
      WHEN u.Reputation >= 1000 THEN 'Expert'
      WHEN u.Reputation >= 100 THEN 'Intermediate'
      ELSE 'Beginner'
    END as ReputationLevel
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.CreationDate >= '2020-01-01'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.CreationDate
),
BountyData AS (
  SELECT 
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyStarted,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) as TotalBountyClosed,
    COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as BountyStartCount,
    COUNT(CASE WHEN v.VoteTypeId = 9 THEN 1 END) as BountyCloseCount
  FROM Votes v
  WHERE v.CreationDate >= '2020-01-01'
    AND v.VoteTypeId IN (8, 9)
  GROUP BY v.PostId
)
SELECT 
  qs.Id as QuestionId,
  qs.Title,
  qs.Score,
  qs.ViewCount,
  qs.AnswerCount,
  qs.CommentCount,
  qs.HasAcceptedAnswer,
  qs.ScoreRank,
  qs.UserQuestionNumber,
  qs.OwnerDisplayName,
  COALESCE(AS.AnswerCount, 0) as ActualAnswerCount,
  COALESCE(AS.TotalAnswerScore, 0) as TotalAnswerScore,
  COALESCE(AS.AvgAnswerScore, 0) as AvgAnswerScore,
  CASE 
    WHEN AS.LatestAnswerDate IS NOT NULL THEN DATEDIFF(DAY, qs.CreationDate, AS.LatestAnswerDate)
    ELSE NULL 
  END as DaysToFirstAnswer,
  SUBSTRING(qs.Tags, 2, LEN(qs.Tags) - 2) as RawTags,
  STRING_AGG(
    CASE 
      WHEN ta.TagName IS NOT NULL THEN ta.TagName 
      ELSE NULL 
    END, 
    ', '
  ) as QuestionTags,
  ud.TotalPosts,
  ud.Questions,
  ud.Answers,
  ud.ReputationLevel,
  COALESCE(bd.TotalBountyStarted, 0) as TotalBountyStarted,
  COALESCE(bd.TotalBountyClosed, 0) as TotalBountyClosed,
  CASE 
    WHEN qs.ViewCount > 0 THEN CAST((qs.Score * 1.0 / qs.ViewCount) AS DECIMAL(10,4))
    ELSE 0 
  END as ScorePerView,
  CASE 
    WHEN qs.AnswerCount > 0 THEN CAST((qs.Score * 1.0 / qs.AnswerCount) AS DECIMAL(10,4))
    ELSE 0 
  END as ScorePerAnswer,
  CASE 
    WHEN qs.CommentCount > 0 THEN CAST((qs.ViewCount * 1.0 / qs.CommentCount) AS DECIMAL(10,4))
    ELSE 0 
  END as ViewsPerComment,
  CASE 
    WHEN qs.CommentCount > 0 AND qs.AnswerCount > 0 THEN CAST((qs.CommentCount * 1.0 / qs.AnswerCount) AS DECIMAL(10,4))
    ELSE 0 
  END as CommentsPerAnswer,
  'QuestionRank' + CAST(qs.ScoreRank AS VARCHAR) as QuestionRankLabel,
  CASE 
    WHEN qs.Score > 100 THEN 'Highly Ranked'
    WHEN qs.Score > 50 THEN 'Moderately Ranked'
    ELSE 'Low Ranked' 
  END as ScoreCategory,
  COALESCE(ud.AccountAgeDays, 0) as AccountAgeInDays,
  CASE 
    WHEN ud.AccountAgeDays > 365 THEN 'Long Term User'
    WHEN ud.AccountAgeDays > 180 THEN 'Regular User'
    ELSE 'New User' 
  END as UserSeniority,
  CASE 
    WHEN bd.TotalBountyStarted > 0 THEN 'Bounty Active'
    WHEN bd.TotalBountyClosed > 0 THEN 'Bounty Closed'
    ELSE 'No Bounty' 
  END as BountyStatus,
  ISNULL(ud.Reputation, 0) as UserReputation,
  CASE 
    WHEN ISNULL(ud.Reputation, 0) >= 10000 THEN 1 
    WHEN ISNULL(ud.Reputation, 0) >= 1000 THEN 2 
    WHEN ISNULL(ud.Reputation, 0) >= 100 THEN 3 
    ELSE 4 
  END as ReputationLevelOrdinal
FROM QuestionStats qs
LEFT JOIN AnswerStats AS ON qs.Id = AS.QuestionId
LEFT JOIN UserActivity ud ON qs.OwnerUserId = ud.UserId
LEFT JOIN BountyData bd ON qs.Id = bd.PostId
LEFT JOIN (
  SELECT 
    p.Id as QuestionId,
    t.TagName
  FROM Posts p
  CROSS APPLY STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><') as tag_parts
  JOIN Tags t ON t.TagName = tag_parts.value
  WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
) tag_mapping ON qs.Id = tag_mapping.QuestionId
LEFT JOIN TagAnalysis ta ON tag_mapping.TagName = ta.TagName
WHERE (COALESCE(AS.AnswerCount, 0) > 0 OR qs.HasAcceptedAnswer = 1)
  AND (qs.ViewCount >= 500 OR qs.Score >= 10)
  AND (ud.TotalPosts >= 1 OR ud.UserId IS NOT NULL)
  AND (
    bd.TotalBountyStarted > 0 
    OR bd.TotalBountyClosed > 0 
    OR bd.PostId IS NULL
  )
  AND EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.ParentId = qs.Id 
      AND p2.PostTypeId = 2 
      AND p2.CreationDate >= '2020-01-01'
    GROUP BY p2.ParentId
    HAVING COUNT(*) > 0
  )
ORDER BY qs.ScoreRank, qs.ViewCount DESC, qs.CreationDate DESC
OPTION (MAXDOP 4);