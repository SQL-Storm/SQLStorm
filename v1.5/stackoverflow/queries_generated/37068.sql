-- {"query": "37068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2071} 
WITH
-- recent activity window
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '180 days'
),
-- tag exploded (assumes Tags like '<tag1><tag2>')
post_tags AS (
  SELECT p.Id AS PostId, lower(trim(t.tag)) AS Tag
  FROM recent_posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND coalesce(p.Tags,'') <> ''
),
-- per-question aggregates: answers, comments, votes, edits, links
question_aggs AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.Score AS QuestionScore,
    q.ViewCount,
    coalesce(a.AnswerCount,0) AS AnswerCount,
    coalesce(c.CommentCount,0) AS CommentCount,
    coalesce(v.UpVotes,0) AS UpVotes,
    coalesce(v.DownVotes,0) AS DownVotes,
    coalesce(e.EditCount,0) AS EditCount,
    coalesce(l.IncomingLinks,0) AS IncomingLinks,
    coalesce(l.OutgoingLinks,0) AS OutgoingLinks,
    q.Tags
  FROM recent_posts q
  LEFT JOIN (
    SELECT ParentId AS QId, count(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - interval '180 days'
    GROUP BY ParentId
  ) a ON a.QId = q.Id
  LEFT JOIN (
    SELECT PostId, count(*) AS CommentCount
    FROM Comments
    WHERE CreationDate >= now() - interval '180 days'
    GROUP BY PostId
  ) c ON c.PostId = q.Id
  LEFT JOIN (
    SELECT p.PostId,
      count(*) FILTER (WHERE vt.Name = 'UpMod' OR vt.Id = 2) AS UpVotes,
      count(*) FILTER (WHERE vt.Name = 'DownMod' OR vt.Id = 3) AS DownVotes
    FROM Votes p
    LEFT JOIN VoteTypes vt ON vt.Id = p.VoteTypeId
    WHERE p.CreationDate >= now() - interval '180 days'
    GROUP BY p.PostId
  ) v ON v.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, count(*) AS EditCount
    FROM PostHistory
    WHERE CreationDate >= now() - interval '180 days'
    GROUP BY PostId
  ) e ON e.PostId = q.Id
  LEFT JOIN (
    SELECT pl.RelatedPostId AS QId, SUM(CASE WHEN pl.PostId = pl.RelatedPostId THEN 0 ELSE 1 END) AS IncomingLinks,
           0 AS OutgoingLinks
    FROM PostLinks pl
    WHERE pl.CreationDate >= now() - interval '180 days'
    GROUP BY pl.RelatedPostId
  ) l_in ON l_in.QId = q.Id
  LEFT JOIN (
    SELECT pl.PostId AS QId, count(*) AS OutgoingLinks
    FROM PostLinks pl
    WHERE pl.CreationDate >= now() - interval '180 days'
    GROUP BY pl.PostId
  ) l_out ON l_out.QId = q.Id
  LEFT JOIN LATERAL (
    SELECT coalesce(l_in.IncomingLinks,0) AS IncomingLinks, coalesce(l_out.OutgoingLinks,0) AS OutgoingLinks
  ) l ON true
),
-- top contributors for each question (answerers + commenters + editors combined)
question_contribs AS (
  SELECT
    q.QuestionId,
    u.Id AS UserId,
    u.DisplayName,
    sum(sc.Score) AS ContributionScore,
    count(*) AS ContributionEvents
  FROM question_aggs q
  JOIN LATERAL (
    -- gather answerers
    SELECT a.OwnerUserId AS UserId, 5 AS Score
    FROM Posts a
    WHERE a.ParentId = q.QuestionId AND a.PostTypeId = 2 AND a.CreationDate >= now() - interval '180 days' AND a.OwnerUserId IS NOT NULL
    UNION ALL
    -- commenters
    SELECT c.UserId, 2 AS Score
    FROM Comments c
    WHERE c.PostId = q.QuestionId AND c.CreationDate >= now() - interval '180 days' AND c.UserId IS NOT NULL
    UNION ALL
    -- editors (from posthistory)
    SELECT ph.UserId, 1 AS Score
    FROM PostHistory ph
    WHERE ph.PostId = q.QuestionId AND ph.CreationDate >= now() - interval '180 days' AND ph.UserId IS NOT NULL
  ) sc ON sc.UserId IS NOT NULL
  JOIN Users u ON u.Id = sc.UserId
  GROUP BY q.QuestionId, u.Id, u.DisplayName
),
-- pick top 3 contributors per question
top_contribs AS (
  SELECT qc.*,
    row_number() OVER (PARTITION BY qc.QuestionId ORDER BY qc.ContributionScore DESC, qc.ContributionEvents DESC, qc.UserId) rn
  FROM question_contribs qc
),
top3_concat AS (
  SELECT
    QuestionId,
    string_agg(DisplayName || ' (' || ContributionScore || ')', ', ' ORDER BY ContributionScore DESC, UserId) AS TopContributors
  FROM top_contribs
  WHERE rn <= 3
  GROUP BY QuestionId
),
-- tag-level aggregates
tag_aggs AS (
  SELECT
    pt.Tag,
    count(DISTINCT pt.PostId) AS QuestionsInWindow,
    sum(qa.AnswerCount) AS TotalAnswers,
    avg(qa.ViewCount) AS AvgViews,
    sum(qa.CommentCount) AS TotalComments,
    sum(qa.UpVotes) AS TotalUpVotes,
    sum(qa.DownVotes) AS TotalDownVotes,
    sum(qa.EditCount) AS TotalEdits
  FROM post_tags pt
  JOIN question_aggs qa ON qa.QuestionId = pt.PostId
  GROUP BY pt.Tag
),
-- detect likely duplicate hotspots: questions that were linked as duplicates most often
dup_hotspots AS (
  SELECT
    pl.RelatedPostId AS CanonQuestionId,
    count(*) AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE (lt.Name = 'Duplicate' OR pl.LinkTypeId = 3) AND pl.CreationDate >= now() - interval '365 days'
  GROUP BY pl.RelatedPostId
),
-- final selection: heavy hitters with combined metrics and windowed trends
score_calc AS (
  SELECT
    qa.QuestionId,
    qa.Title,
    qa.CreationDate,
    qa.OwnerUserId,
    coalesce(u.DisplayName,'<deleted>') AS Owner,
    qa.QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    qa.CommentCount,
    qa.UpVotes,
    qa.DownVotes,
    qa.EditCount,
    coalesce(t3.TopContributors, '') AS TopContributors,
    coalesce(d.DuplicateCount,0) AS DuplicateMentions,
    array_agg(DISTINCT lower(pt.Tag)) FILTER (WHERE pt.Tag IS NOT NULL) AS Tags,
    -- computed composite benchmark score (heavier weight to views, upvotes, recent answers, and duplicates)
    ( 
      (greatest(qa.ViewCount,0)::double precision / nullif((select percentile_cont(0.5) within group (order by ViewCount) from question_aggs),0) ) * 1.2
      + (qa.UpVotes * 3.5)
      + (qa.AnswerCount * 5)
      + (qa.CommentCount * 1.0)
      + (qa.EditCount * 0.8)
      + (coalesce(d.DuplicateCount,0) * 4.0)
      - (qa.DownVotes * 2.0)
    ) AS BenchmarkScore
  FROM question_aggs qa
  LEFT JOIN Users u ON u.Id = qa.OwnerUserId
  LEFT JOIN top3_concat t3 ON t3.QuestionId = qa.QuestionId
  LEFT JOIN dup_hotspots d ON d.CanonQuestionId = qa.QuestionId
  LEFT JOIN post_tags pt ON pt.PostId = qa.QuestionId
  GROUP BY qa.QuestionId, qa.Title, qa.CreationDate, qa.OwnerUserId, u.DisplayName, qa.QuestionScore, qa.ViewCount, qa.AnswerCount, qa.CommentCount, qa.UpVotes, qa.DownVotes, qa.EditCount, t3.TopContributors, d.DuplicateCount
)
SELECT
  sc.QuestionId,
  sc.Title,
  sc.Owner,
  sc.CreationDate,
  sc.Tags,
  sc.QuestionScore,
  sc.ViewCount,
  sc.AnswerCount,
  sc.UpVotes,
  sc.DownVotes,
  sc.CommentCount,
  sc.EditCount,
  sc.DuplicateMentions,
  sc.TopContributors,
  round(sc.BenchmarkScore,2) AS BenchmarkScore,
  -- rank within tags by benchmark score
  rank() OVER (PARTITION BY tg.Tag ORDER BY sc.BenchmarkScore DESC) AS TagRank,
  dense_rank() OVER (ORDER BY sc.BenchmarkScore DESC) AS GlobalRank
FROM score_calc sc
LEFT JOIN LATERAL (
  SELECT unnest(coalesce(sc.Tags, array[]::text[])) AS Tag
) tg ON true
ORDER BY sc.BenchmarkScore DESC
LIMIT 200;