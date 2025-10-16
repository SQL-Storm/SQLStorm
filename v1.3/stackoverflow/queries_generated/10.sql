-- {"query": "10.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2229} 
WITH
-- Top contributors: users with many posts, answers, and reputation weight
user_post_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
    COALESCE(SUM(p.Score),0) AS PostsScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- Recent activity window per user: last 365 days
recent_activity AS (
  SELECT
    up.UserId,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now() - INTERVAL '365 days') AS RecentQuestions,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - INTERVAL '365 days') AS RecentAnswers,
    COALESCE(SUM(vb.UpVotes),0) AS RecentUpVotesReceived,
    COALESCE(SUM(vb.DownVotes),0) AS RecentDownVotesReceived
  FROM user_post_stats up
  LEFT JOIN Posts p ON p.OwnerUserId = up.UserId AND p.CreationDate >= now() - INTERVAL '365 days'
  LEFT JOIN (
    -- aggregate votes received on posts by user in last year, bucketed
    SELECT p.OwnerUserId AS OwnerUserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE p.CreationDate >= now() - INTERVAL '365 days'
    GROUP BY p.OwnerUserId
  ) vb ON vb.OwnerUserId = up.UserId
  GROUP BY up.UserId
),
-- Tag parsing: explode Tags string like '<tag1><tag2>' into tag rows (PostTypeId=1)
question_tags AS (
  SELECT
    p.Id AS QuestionId,
    TRIM(tg) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT regexp_split_to_table(
      COALESCE(substring(p.Tags FROM 2 FOR greatest(char_length(p.Tags)-2,0)),''),
      '><'
    ) AS tg
  ) s(tg)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
-- Popular tag metrics
tag_metrics AS (
  SELECT
    qt.Tag,
    COUNT(DISTINCT qt.QuestionId) AS QuestionsWithTag,
    COUNT(a.Id) FILTER (WHERE a.Score >= 0) AS AnswersForTaggedQuestions,
    AVG(q.Score) AS AvgQuestionScore,
    MAX(q.ViewCount) AS MaxViews,
    COUNT(DISTINCT q.OwnerUserId) AS DistinctAskers
  FROM question_tags qt
  JOIN Posts q ON q.Id = qt.QuestionId
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  GROUP BY qt.Tag
),
-- Identify likely duplicates via PostLinks and text similarity (simple heuristic)
duplicate_candidates AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.CreationDate,
    lt.Name AS LinkType,
    p1.Title AS Title1,
    p2.Title AS Title2,
    -- crude similarity: number of shared words in titles
    (
      SELECT COUNT(*)
      FROM (
        SELECT unnest(string_to_array(lower(regexp_replace(coalesce(p1.Title,''),'[^a-z0-9 ]',' ','g')), ' ')) AS w1
        INTERSECT
        SELECT unnest(string_to_array(lower(regexp_replace(coalesce(p2.Title,''),'[^a-z0-9 ]',' ','g')), ' ')) AS w2
      ) s
    ) AS SharedTitleWords
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Posts p1 ON p1.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE lt.Name IN ('Duplicate','Linked')
),
-- Windowed ranking of answers per question with various signals
answer_rankings AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore,
    RANK() OVER (PARTITION BY a.ParentId ORDER BY ABS(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) ASC) AS RankByProximity,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE v.Id IS NOT NULL) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE v.Id IS NOT NULL) AS DownVotes
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId
  LEFT JOIN Comments c ON c.PostId = a.Id
  LEFT JOIN Votes v ON v.PostId = a.Id
  WHERE a.PostTypeId = 2
  GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.CreationDate
),
-- Users with extremes and nulls to stress null logic
null_and_edge_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.WebsiteUrl,
    u.Location,
    u.AboutMe,
    CASE WHEN u.WebsiteUrl IS NULL THEN 'no-site' WHEN u.WebsiteUrl = '' THEN 'empty-site' ELSE 'has-site' END AS SiteBucket,
    COALESCE(u.Views,0) AS ViewsCoalesced,
    (u.LastAccessDate IS NULL) AS NeverAccessed
  FROM Users u
),
-- final aggregation combining many signals for benchmarking
candidate_aggregation AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.QuestionsCount,
    up.AnswersCount,
    ra.RecentQuestions,
    ra.RecentAnswers,
    ra.RecentUpVotesReceived,
    ra.RecentDownVotesReceived,
    COALESCE(tm.QuestionsWithTag,0) AS FavTagQuestions,
    tm.Tag AS RepresentativeTag,
    ar_top.AnswerId AS TopAnswerId,
    ar_top.Score AS TopAnswerScore,
    ar_top.CommentCount AS TopAnswerComments,
    dc.RelatedPostId AS DuplicateOf,
    dc.SharedTitleWords,
    nu.SiteBucket,
    nu.ViewsCoalesced,
    nu.NeverAccessed,
    -- complex expression mixing nulls, casts, math and strings
    (up.Reputation::numeric * (1 + GREATEST(LEAST(COALESCE(ra.RecentUpVotesReceived,0) - COALESCE(ra.RecentDownVotesReceived,0), 100), -100)/100.0))
      + COALESCE(ar_top.Score,0) * NULLIF(LOG(1 + COALESCE(ar_top.CommentCount,0)),0)
      - COALESCE(tm.AvgQuestionScore,0) AS InfluenceScore,
    -- flag for oddities: user with many answers but no accepted answers
    CASE WHEN up.AnswersCount > 50 AND NOT EXISTS (
      SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId IS NOT NULL AND EXISTS (
        SELECT 1 FROM Posts a WHERE a.Id = q.AcceptedAnswerId AND a.OwnerUserId = up.UserId
      )
    ) THEN 1 ELSE 0 END AS HighAnswersNoAccepted
  FROM user_post_stats up
  LEFT JOIN recent_activity ra ON ra.UserId = up.UserId
  LEFT JOIN LATERAL (
    SELECT tm.Tag, tm.QuestionsWithTag, tm.AvgQuestionScore
    FROM tag_metrics tm
    ORDER BY tm.QuestionsWithTag DESC NULLS LAST
    LIMIT 1
  ) tm ON TRUE
  LEFT JOIN LATERAL (
    SELECT ar.AnswerId, ar.Score, ar.CommentCount
    FROM answer_rankings ar
    WHERE ar.OwnerUserId = up.UserId
    ORDER BY ar.Score DESC NULLS LAST, ar.CommentCount DESC
    LIMIT 1
  ) ar_top ON TRUE
  LEFT JOIN LATERAL (
    SELECT dc.RelatedPostId, dc.SharedTitleWords
    FROM duplicate_candidates dc
    JOIN Posts p ON p.Id = dc.PostId
    WHERE p.OwnerUserId = up.UserId
    ORDER BY dc.SharedTitleWords DESC NULLS LAST
    LIMIT 1
  ) dc ON TRUE
  LEFT JOIN null_and_edge_users nu ON nu.Id = up.UserId
)
SELECT
  ca.UserId,
  ca.DisplayName,
  ca.Reputation,
  ca.QuestionsCount,
  ca.AnswersCount,
  ca.RecentQuestions,
  ca.RecentAnswers,
  ca.RecentUpVotesReceived,
  ca.RecentDownVotesReceived,
  ca.RepresentativeTag,
  ca.FavTagQuestions,
  ca.TopAnswerId,
  ca.TopAnswerScore,
  ca.TopAnswerComments,
  ca.DuplicateOf,
  ca.SharedTitleWords,
  ca.SiteBucket,
  ca.ViewsCoalesced,
  ca.NeverAccessed,
  ROUND(ca.InfluenceScore::numeric,2) AS InfluenceScore,
  ca.HighAnswersNoAccepted,
  -- rank users by computed influence across the result set with ties broken:
  RANK() OVER (ORDER BY ca.InfluenceScore DESC NULLS LAST, ca.Reputation DESC) AS InfluenceRank
FROM candidate_aggregation ca
WHERE (ca.QuestionsCount + ca.AnswersCount) > 0
  AND (ca.Reputation IS NOT NULL AND ca.Reputation >= 0)
  AND (ca.FavTagQuestions IS NULL OR ca.FavTagQuestions >= 0)
ORDER BY InfluenceScore DESC NULLS LAST, ca.Reputation DESC
LIMIT 250;