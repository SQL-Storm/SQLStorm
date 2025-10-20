-- {"query": "37074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2219} 
WITH
-- hot tags: tags with many posts and recent activity
TagStats AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count AS GlobalCount,
    COALESCE(MAX(p.LastActivityDate), '1970-01-01'::timestamp) AS LastActivity,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE ('%<' || t.TagName || '>%')
  GROUP BY t.Id, t.TagName, t.Count
),
-- compute user engagement metrics: answers, questions, average score, accepted rate, recent activity
UserMetrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
    AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
    SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (
      SELECT 1 FROM Posts q WHERE q.Id = p.ParentId AND q.AcceptedAnswerId = p.Id
    ) THEN 1 ELSE 0 END) AS AcceptsAsAnswer,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL) AS AnswerCandidates,
    CASE WHEN COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL) = 0
         THEN 0
         ELSE ROUND(100.0 * SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (
                     SELECT 1 FROM Posts q WHERE q.Id = p.ParentId AND q.AcceptedAnswerId = p.Id
                   ) THEN 1 ELSE 0 END) / NULLIF(COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL),0),2)
    END AS AcceptRatePct,
    MAX(u.LastAccessDate) AS LastAccessDate,
    COUNT(b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- compute tag-user affinity: how many answers a user gave to questions with a tag, recent tag expertise
TagUserAff AS (
  SELECT
    t.Id AS TagId,
    u.Id AS UserId,
    COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswersToTag,
    AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
    MAX(a.CreationDate) AS LastAnsweredAt
  FROM Tags t
  JOIN Posts q ON q.PostTypeId = 1 AND q.Tags LIKE ('%<' || t.TagName || '>%')
  JOIN Posts a ON a.PostTypeId = 2 AND a.ParentId = q.Id
  JOIN Users u ON u.Id = a.OwnerUserId
  GROUP BY t.Id, u.Id
),
-- recent controversies: posts with high score and many downvotes or many edits/comments
PostControversy AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (5,6,24)) AS EditOrSuggestionCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    COALESCE(NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0),1) AS UpVotesSafe,
    ROUND(
      CASE WHEN SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) = 0 THEN 0
      ELSE 100.0 * SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END),0)
      END
      ,2) AS DownvotePct
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.CommentCount
),
-- pick hot tags and their top experts
HotTagExperts AS (
  SELECT
    ts.TagId,
    ts.TagName,
    ts.GlobalCount,
    ts.LastActivity,
    tua.UserId,
    um.DisplayName,
    tua.AnswersToTag,
    tua.AvgAnswerScore,
    ROW_NUMBER() OVER (PARTITION BY ts.TagId ORDER BY tua.AnswersToTag DESC NULLS LAST, tua.AvgAnswerScore DESC NULLS LAST) AS TagRank
  FROM TagStats ts
  JOIN TagUserAff tua ON tua.TagId = ts.TagId
  JOIN UserMetrics um ON um.UserId = tua.UserId
  WHERE ts.GlobalCount > 100 -- reasonably popular tags
    AND ts.LastActivity > (now() - interval '1 year')
)
-- final heavy query: combine lots of metrics, window functions, JSON aggregation and costly joins to stress the engine
SELECT
  ht.TagId,
  ht.TagName,
  ht.GlobalCount,
  ht.LastActivity,
  jsonb_build_object(
    'TopExperts',
    (SELECT jsonb_agg(jsonb_build_object(
        'UserId', he.UserId,
        'DisplayName', he.DisplayName,
        'AnswersToTag', he.AnswersToTag,
        'AvgAnswerScore', ROUND(COALESCE(he.AvgAnswerScore,0)::numeric,2)
      ) ORDER BY he.AnswersToTag DESC NULLS LAST, he.AvgAnswerScore DESC NULLS LAST)
     FROM HotTagExperts he WHERE he.TagId = ht.TagId AND he.TagRank <= 5),
    'RecentControversialThreads',
    (SELECT jsonb_agg(jsonb_build_object(
        'PostId', p.Id,
        'Title', LEFT(p.Title,120),
        'PostType', CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END,
        'Score', p.Score,
        'Views', p.ViewCount,
        'CommentCount', p.CommentCount,
        'DownvotePct', ROUND(pc.DownvotePct::numeric,2),
        'EditOrSuggestionCount', pc.EditOrSuggestionCount
      ) ORDER BY pc.DownvotePct DESC NULLS LAST, pc.EditOrSuggestionCount DESC NULLS LAST LIMIT 7)
     FROM Posts p
     JOIN PostControversy pc ON pc.Id = p.Id
     WHERE p.PostTypeId = 1
       AND p.Tags LIKE ('%<' || ht.TagName || '>%')
       AND (pc.DownvotePct > 10 OR pc.EditOrSuggestionCount >= 3)
       AND p.CreationDate > (now() - interval '3 year')
    )
  ) AS TagInsights,
  -- overall community metrics for the tag
  (SELECT jsonb_build_object(
      'TotalQuestions', COUNT(q.Id),
      'MedianAnswersPerQuestion', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(a_counts.cnt,0)) OVER (),
      'AvgViews', ROUND(AVG(q.ViewCount)::numeric,2),
      'TopAnswerersLastYear', (SELECT jsonb_agg(jsonb_build_object('UserId', tu.UserId, 'DisplayName', um2.DisplayName, 'Answers', tu.AnswersToTag) ORDER BY tu.AnswersToTag DESC LIMIT 10)
                              FROM TagUserAff tu JOIN UserMetrics um2 ON um2.UserId = tu.UserId
                              WHERE tu.TagId = ht.TagId AND tu.LastAnsweredAt > (now() - interval '1 year'))
    )
   FROM Posts q
   LEFT JOIN (
     SELECT ParentId, COUNT(*) AS cnt FROM Posts WHERE PostTypeId = 2 GROUP BY ParentId
   ) a_counts ON a_counts.ParentId = q.Id
   WHERE q.PostTypeId = 1 AND q.Tags LIKE ('%<' || ht.TagName || '>%')
  ) AS CommunityMetrics,
  -- cross-tag similarity: top 3 tags sharing many common answerers (expensive subquery)
  (SELECT jsonb_agg(jsonb_build_object('OtherTag', ot.TagName, 'CommonActiveAnswerers', cnt) ORDER BY cnt DESC LIMIT 3)
   FROM (
     SELECT t2.TagName, COUNT(DISTINCT a.OwnerUserId) AS cnt
     FROM Posts q1
     JOIN Posts a ON a.PostTypeId = 2 AND a.ParentId = q1.Id
     JOIN Posts q2 ON q2.PostTypeId = 1 AND q2.Tags LIKE ('%<' || t2.TagName || '>%')
     JOIN Tags t2 ON q2.Tags LIKE ('%<' || t2.TagName || '>%')
     WHERE q1.PostTypeId = 1
       AND q1.Tags LIKE ('%<' || ht.TagName || '>%')
       AND t2.Id <> ht.TagId
       AND a.CreationDate > (now() - interval '2 year')
     GROUP BY t2.TagName
   ) x
  ) AS CrossTagSimilarity,
  now() AS GeneratedAt
FROM TagStats ht
WHERE ht.GlobalCount > 100
ORDER BY ht.LastActivity DESC
LIMIT 25;