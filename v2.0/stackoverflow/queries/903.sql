-- {"query": "903.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2699}
WITH
q AS (
  SELECT p.Id AS QuestionId,
         p.CreationDate AS QuestionCreation,
         p.OwnerUserId AS QuestionOwnerId,
         p.Score AS QuestionScore,
         p.ViewCount,
         p.Tags,
         p.AcceptedAnswerId,
         COALESCE(NULLIF(TRIM(p.Title), ''), '[no title]') AS NormalizedTitle
  FROM Posts p
  WHERE p.PostTypeId = 1
),
a AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId AS AnswerOwnerId,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreation
  FROM Posts a
  WHERE a.PostTypeId = 2
),
user_activity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate AS UserCreated,
         u.LastAccessDate AS UserLastAccess,
         u.UpVotes,
         u.DownVotes,
         u.Views AS ProfileViews,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotesCast,
         COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
q_answer_stats AS (
  SELECT
    q.QuestionId,
    COUNT(a.AnswerId) AS TotalAnswers,
    SUM(CASE WHEN a.AnswerId = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAccepted,
    AVG(CAST(a.AnswerScore AS numeric)) AS AvgAnswerScore,
    MAX(a.AnswerScore) AS MaxAnswerScore,
    MIN(a.AnswerScore) AS MinAnswerScore,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY a.AnswerScore) AS MedianAnswerScore,
    MIN(a.AnswerCreation) AS FirstAnswerAt,
    MAX(a.AnswerCreation) AS LastAnswerAt
  FROM q
  LEFT JOIN a ON a.QuestionId = q.QuestionId
  GROUP BY q.QuestionId
),
q_comment_stats AS (
  SELECT
    p.Id AS QuestionId,
    COUNT(c.Id) FILTER (WHERE c.Id IS NOT NULL) AS CommentCount,
    COALESCE(SUM(c.Score), 0) AS CommentScoreSum,
    MAX(c.Score) AS MaxCommentScore
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
tag_expansion AS (
  SELECT
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, GREATEST(length(q.Tags)-2,0)), '><')) AS tag
  FROM q
  WHERE q.Tags IS NOT NULL AND q.Tags LIKE '<%>'
),
top_tags AS (
  SELECT tag,
         COUNT(*) AS TagUsage,
         RANK() OVER (ORDER BY COUNT(*) DESC, tag ASC) AS tag_rank
  FROM tag_expansion
  GROUP BY tag
),
q_tag_profile AS (
  SELECT te.QuestionId,
         COUNT(*) AS TagCount,
         SUM(CASE WHEN tt.tag_rank <= 100 THEN 1 ELSE 0 END) AS Top100TagHits,
         string_agg(te.tag, ',' ORDER BY te.tag) AS TagListCSV
  FROM tag_expansion te
  LEFT JOIN top_tags tt ON tt.tag = te.tag
  GROUP BY te.QuestionId
),
close_events AS (
  SELECT ph.PostId,
         MIN(ph.CreationDate) AS FirstCloseDate,
         MAX(ph.CreationDate) AS LastCloseDate,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesEvents,
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN NULLIF(ph.Comment, '') END) AS AnyCloseReasonIdText
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11)
  GROUP BY ph.PostId
),
dup_links AS (
  SELECT pl.PostId AS QuestionId,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS RelatedLinks
  FROM PostLinks pl
  GROUP BY pl.PostId
),
question_quality AS (
  SELECT
    q.QuestionId,
    q.QuestionCreation,
    q.QuestionOwnerId,
    q.QuestionScore,
    q.ViewCount,
    qa.TotalAnswers,
    qa.HasAccepted,
    qa.AvgAnswerScore,
    qa.FirstAnswerAt,
    qc.CommentCount,
    qc.CommentScoreSum,
    qt.TagCount,
    qt.Top100TagHits,
    d.DuplicateLinks,
    d.RelatedLinks,
    c.FirstCloseDate,
    c.CloseVotesEvents,
    CASE
      WHEN qa.TotalAnswers IS NULL OR qa.TotalAnswers = 0 THEN NULL
      ELSE EXTRACT(EPOCH FROM (qa.FirstAnswerAt - q.QuestionCreation))/60.0
    END AS MinutesToFirstAnswer,
    CASE
      WHEN q.ViewCount IS NULL OR q.ViewCount = 0 THEN NULL
      ELSE (CAST(q.QuestionScore AS numeric) / NULLIF(q.ViewCount,0))
    END AS ScorePerView,
    CASE
      WHEN qc.CommentCount > 0 THEN (CAST(qc.CommentScoreSum AS numeric) / qc.CommentCount)
      ELSE NULL
    END AS AvgCommentScore,
    CASE
      WHEN qt.TagCount >= 5 THEN 'broad'
      WHEN qt.TagCount BETWEEN 3 AND 4 THEN 'normal'
      WHEN qt.TagCount BETWEEN 1 AND 2 THEN 'narrow'
      ELSE 'untagged'
    END AS TagBreadthBucket
  FROM q
  LEFT JOIN q_answer_stats qa ON qa.QuestionId = q.QuestionId
  LEFT JOIN q_comment_stats qc ON qc.QuestionId = q.QuestionId
  LEFT JOIN q_tag_profile qt ON qt.QuestionId = q.QuestionId
  LEFT JOIN dup_links d ON d.QuestionId = q.QuestionId
  LEFT JOIN close_events c ON c.PostId = q.QuestionId
),
owner_rollup AS (
  SELECT
    qa.QuestionOwnerId AS UserId,
    COUNT(*) AS QuestionsAuthored,
    SUM(CASE WHEN qa.HasAccepted = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    AVG(CAST(qa.QuestionScore AS numeric)) AS AvgQuestionScore,
    percentile_cont(0.9) WITHIN GROUP (ORDER BY qa.ViewCount) AS P90Views
  FROM question_quality qa
  GROUP BY qa.QuestionOwnerId
),
recent_activity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')) AS QuestionsLastYear,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')) AS AnswersLastYear,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2 AND p.Score >= 5 AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')) AS GoodAnswersLastYear
  FROM Posts p
  GROUP BY p.OwnerUserId
),
user_score AS (
  SELECT
    ua.UserId,
    ua.Reputation,
    ua.UpVotes,
    ua.DownVotes,
    ua.NetVotesCast,
    COALESCE(ua.GoldBadges,0) AS GoldBadges,
    COALESCE(ua.SilverBadges,0) AS SilverBadges,
    COALESCE(ua.BronzeBadges,0) AS BronzeBadges,
    oru.QuestionsAuthored,
    oru.QuestionsWithAcceptedAnswer,
    oru.AvgQuestionScore,
    oru.P90Views,
    ra.QuestionsLastYear,
    ra.AnswersLastYear,
    ra.GoodAnswersLastYear,
    (
      COALESCE(ua.Reputation,0) +
      50 * COALESCE(ra.GoodAnswersLastYear,0) +
      10 * COALESCE(oru.QuestionsWithAcceptedAnswer,0) +
      5 * GREATEST(COALESCE(ua.UpVotes,0) - COALESCE(ua.DownVotes,0), 0) +
      100 * COALESCE(ua.GoldBadges,0) + 25 * COALESCE(ua.SilverBadges,0) + 5 * COALESCE(ua.BronzeBadges,0) +
      0.1 * COALESCE(oru.P90Views,0)
    ) AS EngagementScore
  FROM user_activity ua
  LEFT JOIN owner_rollup oru ON oru.UserId = ua.UserId
  LEFT JOIN recent_activity ra ON ra.UserId = ua.UserId
),
question_ranked AS (
  SELECT
    qq.QuestionId,
    qq.QuestionCreation,
    qq.QuestionOwnerId,
    qq.QuestionScore,
    qq.ViewCount,
    qq.TotalAnswers,
    qq.HasAccepted,
    qq.AvgAnswerScore,
    qq.MinutesToFirstAnswer,
    qq.ScorePerView,
    qq.AvgCommentScore,
    qq.TagBreadthBucket,
    qq.DuplicateLinks,
    qq.RelatedLinks,
    qq.FirstCloseDate,
    qq.CloseVotesEvents,
    us.EngagementScore AS EngagementScore,
    CASE WHEN qq.TagBreadthBucket = 'untagged' THEN 'other' ELSE qq.TagBreadthBucket END AS BucketPartition,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN qq.TagBreadthBucket = 'untagged' THEN 'other' ELSE qq.TagBreadthBucket END
      ORDER BY
        COALESCE(qq.HasAccepted,0) DESC,
        COALESCE(qq.TotalAnswers,0) DESC,
        COALESCE(qq.ScorePerView, -1) DESC,
        COALESCE(qq.AvgCommentScore, -1) DESC,
        COALESCE(us.EngagementScore, -1) DESC,
        qq.QuestionCreation DESC
    ) AS BucketRank
  FROM question_quality qq
  LEFT JOIN user_score us ON us.UserId = qq.QuestionOwnerId
),
flagged_or_hot AS (
  SELECT
    q.QuestionId,
    MAX(CASE WHEN ph.PostHistoryTypeId IN (52,53) THEN 1 ELSE 0 END) AS HasHotEvent,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 50) AS CommunityBumps
  FROM q
  LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId
  GROUP BY q.QuestionId
),
final_set AS (
  SELECT
    qr.QuestionId,
    qr.QuestionCreation,
    qr.QuestionOwnerId,
    qr.QuestionScore,
    qr.ViewCount,
    qr.TotalAnswers,
    qr.HasAccepted,
    qr.AvgAnswerScore,
    qr.MinutesToFirstAnswer,
    qr.ScorePerView,
    qr.AvgCommentScore,
    qr.TagBreadthBucket,
    qr.DuplicateLinks,
    qr.RelatedLinks,
    qr.FirstCloseDate,
    qr.CloseVotesEvents,
    qr.EngagementScore,
    fo.HasHotEvent,
    fo.CommunityBumps,
    qr.BucketRank
  FROM question_ranked qr
  LEFT JOIN flagged_or_hot fo ON fo.QuestionId = qr.QuestionId
  WHERE
    (
      qr.HasAccepted = 1
      OR COALESCE(qr.TotalAnswers,0) >= 3
      OR (fo.HasHotEvent = 1 AND COALESCE(qr.ScorePerView,0) > 0)
    )
),
candidate_set AS (
  SELECT fs.QuestionId,
         fs.QuestionCreation,
         fs.QuestionOwnerId,
         fs.QuestionScore,
         fs.ViewCount,
         fs.TotalAnswers,
         fs.HasAccepted,
         fs.AvgAnswerScore,
         fs.MinutesToFirstAnswer,
         fs.ScorePerView,
         fs.AvgCommentScore,
         fs.TagBreadthBucket,
         fs.DuplicateLinks,
         fs.RelatedLinks,
         fs.FirstCloseDate,
         fs.CloseVotesEvents,
         fs.EngagementScore,
         fs.HasHotEvent,
         fs.CommunityBumps,
         fs.BucketRank,
         'A:TopByBucket' AS SourceSet
  FROM final_set fs
  WHERE fs.BucketRank <= 50

  UNION ALL

  SELECT fs.QuestionId,
         fs.QuestionCreation,
         fs.QuestionOwnerId,
         fs.QuestionScore,
         fs.ViewCount,
         fs.TotalAnswers,
         fs.HasAccepted,
         fs.AvgAnswerScore,
         fs.MinutesToFirstAnswer,
         fs.ScorePerView,
         fs.AvgCommentScore,
         fs.TagBreadthBucket,
         fs.DuplicateLinks,
         fs.RelatedLinks,
         fs.FirstCloseDate,
         fs.CloseVotesEvents,
         fs.EngagementScore,
         fs.HasHotEvent,
         fs.CommunityBumps,
         fs.BucketRank,
         'B:HighEngagementButLowAnswers' AS SourceSet
  FROM final_set fs
  WHERE COALESCE(fs.EngagementScore,0) > (
          SELECT percentile_cont(0.8) WITHIN GROUP (ORDER BY EngagementScore)
          FROM final_set
        )
    AND COALESCE(fs.TotalAnswers,0) <= 1

  UNION ALL

  SELECT fs.QuestionId,
         fs.QuestionCreation,
         fs.QuestionOwnerId,
         fs.QuestionScore,
         fs.ViewCount,
         fs.TotalAnswers,
         fs.HasAccepted,
         fs.AvgAnswerScore,
         fs.MinutesToFirstAnswer,
         fs.ScorePerView,
         fs.AvgCommentScore,
         fs.TagBreadthBucket,
         fs.DuplicateLinks,
         fs.RelatedLinks,
         fs.FirstCloseDate,
         fs.CloseVotesEvents,
         fs.EngagementScore,
         fs.HasHotEvent,
         fs.CommunityBumps,
         fs.BucketRank,
         'C:LateFirstAnswer' AS SourceSet
  FROM final_set fs
  WHERE fs.MinutesToFirstAnswer > (
          SELECT AVG(MinutesToFirstAnswer) + STDDEV_POP(MinutesToFirstAnswer)
          FROM final_set
          WHERE MinutesToFirstAnswer IS NOT NULL
        )
),
deduped AS (
  SELECT QuestionId,
         QuestionCreation,
         QuestionOwnerId,
         QuestionScore,
         ViewCount,
         TotalAnswers,
         HasAccepted,
         AvgAnswerScore,
         MinutesToFirstAnswer,
         ScorePerView,
         AvgCommentScore,
         TagBreadthBucket,
         DuplicateLinks,
         RelatedLinks,
         FirstCloseDate,
         CloseVotesEvents,
         EngagementScore,
         HasHotEvent,
         CommunityBumps,
         BucketRank,
         SourceSet,
         ROW_NUMBER() OVER (
           PARTITION BY QuestionId
           ORDER BY
             CASE SourceSet WHEN 'A:TopByBucket' THEN 1 WHEN 'B:HighEngagementButLowAnswers' THEN 2 ELSE 3 END,
             BucketRank NULLS LAST
         ) AS rn
  FROM candidate_set
)
SELECT
  QuestionId,
  QuestionCreation,
  QuestionOwnerId,
  QuestionScore,
  ViewCount,
  TotalAnswers,
  HasAccepted,
  AvgAnswerScore,
  MinutesToFirstAnswer,
  ScorePerView,
  AvgCommentScore,
  TagBreadthBucket,
  DuplicateLinks,
  RelatedLinks,
  FirstCloseDate,
  CloseVotesEvents,
  EngagementScore,
  HasHotEvent,
  CommunityBumps,
  BucketRank,
  SourceSet
FROM deduped
WHERE rn = 1
ORDER BY
  COALESCE(HasAccepted,0) DESC,
  COALESCE(TotalAnswers,0) DESC,
  COALESCE(ScorePerView,-1) DESC,
  COALESCE(EngagementScore,-1) DESC,
  QuestionCreation DESC
LIMIT 500;