-- {"query": "46.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2668} 
WITH
-- recent activity per post including last comment and last history
post_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    COALESCE(MAX(ph.CreationDate), p.LastActivityDate, p.LastEditDate, p.CreationDate) AS LastKnownActivity,
    max(c.CreationDate) FILTER (WHERE c.Id IS NOT NULL) AS LastCommentDate,
    COUNT(c.Id) FILTER (WHERE c.Id IS NOT NULL) AS CommentCountComputed
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id, p.PostTypeId, p.ParentId, p.OwnerUserId, p.CreationDate, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.LastActivityDate, p.LastEditDate
),
-- compute high-level user aggregates with window functions
user_aggregates AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Views,0) AS ProfileViews,
    COALESCE(SUM(p.Score) FILTER (WHERE p.OwnerUserId = u.Id),0) AS SumPostScores,
    COALESCE(COUNT(DISTINCT b.Id) FILTER (WHERE b.UserId = u.Id),0) AS BadgeCount,
    COALESCE(MAX(b.Class) FILTER (WHERE b.UserId = u.Id), 0) AS HighestBadgeClass,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score) FILTER (WHERE p.OwnerUserId = u.Id),0) DESC, u.Reputation DESC NULLS LAST) AS RankByScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
-- identify candidate question-answer pairs including correlated subquery for accepted and highest scoring answer
qa_pairs AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.Tags,
    q.OwnerUserId AS QOwner,
    q.CreationDate AS QCreated,
    q.Score AS QScore,
    q.ViewCount AS QViews,
    a.Id AS AnswerId,
    a.OwnerUserId AS AOwner,
    a.CreationDate AS ACreated,
    a.Score AS AScore,
    a.ParentId,
    -- correlated subquery: is this the accepted answer? if question.AcceptedAnswerId is null, compute "best" via score/time heuristic
    CASE
      WHEN q.AcceptedAnswerId = a.Id THEN true
      WHEN q.AcceptedAnswerId IS NULL THEN
        a.Id = (
          SELECT ap.Id FROM Posts ap
          WHERE ap.ParentId = q.Id
          ORDER BY COALESCE(ap.Score,0) DESC, ap.CreationDate ASC
          LIMIT 1
        )
      ELSE false
    END AS IsAcceptedOrBestGuess,
    -- text-based heuristic: does answer body quote the title words?
    (CASE WHEN a.Body IS NOT NULL AND q.Title IS NOT NULL THEN
      (length(regexp_replace(lower(a.Body), '\s+', ' ', 'g')) - length(replace(lower(a.Body), split_part(lower(q.Title),' ',1), ''))) > 0
     ELSE false END) AS TitleWordQuoted
  FROM Posts q
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
),
-- examine links between posts and classify duplicates vs references
post_link_analysis AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    p1.PostTypeId AS PostType_Post,
    p2.PostTypeId AS PostType_Related,
    CASE WHEN pl.PostId = pl.RelatedPostId THEN 'self' WHEN pl.LinkTypeId = 3 THEN 'duplicate' ELSE 'linked' END AS LinkClassification,
    COUNT(*) OVER (PARTITION BY pl.PostId) AS OutgoingLinksCount
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Posts p1 ON p1.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
),
-- compute complex tag metrics: explode tags string ' <tag1><tag2>...' into rows
exploded_tags AS (
  SELECT
    p.Id AS PostId,
    trim(tg) AS Tag,
    p.CreationDate,
    p.Score,
    p.ViewCount
  FROM Posts p
  CROSS JOIN LATERAL (
    CASE
      WHEN p.Tags IS NULL THEN ARRAY[]::text[]
      ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')
    END
  ) AS arr(tags_array)
  CROSS JOIN LATERAL unnest(arr.tags_array) AS tg
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
tag_popularity AS (
  SELECT
    et.Tag,
    COUNT(DISTINCT et.PostId) AS QuestionCount,
    SUM(et.Score) AS ScoreSum,
    AVG(et.ViewCount) AS AvgViews,
    rank() OVER (ORDER BY COUNT(DISTINCT et.PostId) DESC) AS PopularityRank
  FROM exploded_tags et
  GROUP BY et.Tag
),
-- combine many signals for a scoring function per question
question_scores AS (
  SELECT
    pa.PostId AS QuestionId,
    pa.Title,
    pa.Tags,
    pa.OwnerUserId,
    pa.CreationDate,
    pa.Score AS BaseScore,
    pa.ViewCount,
    pa.AnswerCount,
    pa.FavoriteCount,
    ua.Reputation AS OwnerReputation,
    ua.BadgeCount AS OwnerBadgeCount,
    COALESCE(tpop.PopularityRank, 999999) AS TagPopularityRank,
    COALESCE(pl.OutgoingLinksCount,0) AS OutgoingLinks,
    pa.CommentCountComputed,
    -- complex scoring expression mixing null logic, exponentials, and string checks
    (
      (COALESCE(pa.Score,0) * GREATEST(LOG(GREATEST(pa.ViewCount,1))::numeric,1) )
      + (COALESCE(pa.AnswerCount,0) * 50)
      + (COALESCE(pa.FavoriteCount,0) * 20)
      + (CASE WHEN pa.Title ILIKE '%how to%' OR pa.Title ILIKE '%how%' THEN 200 ELSE 0 END)
      + (CASE WHEN pa.Tags ILIKE '%<sql>% ' OR pa.Tags ILIKE '%<sql>%' THEN 150 ELSE 0 END)
      - LEAST(COALESCE(ua.Reputation,0)::numeric / 100, 300)
      - (COALESCE(CASE WHEN pa.LastKnownActivity < now() - interval '365 days' THEN 100 ELSE 0 END,0))
      - (COALESCE(TagPenalty.SubPenalty,0))
      + (COALESCE(LEAST(pl.OutgoingLinksCount,5) * 10,0))
      + (CASE WHEN pa.Tags IS NULL THEN -500 ELSE 0 END)
    ) AS CompositeScore
  FROM post_activity pa
  LEFT JOIN user_aggregates ua ON ua.UserId = pa.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT SUM(CASE WHEN tp.PopularityRank > 100 THEN 50 ELSE 0 END) AS SubPenalty
    FROM tag_popularity tp
    WHERE EXISTS (
      SELECT 1 FROM exploded_tags et WHERE et.PostId = pa.PostId AND et.Tag = tp.Tag
    )
  ) AS TagPenalty ON true
  LEFT JOIN post_link_analysis pl ON pl.PostId = pa.PostId
  WHERE pa.PostTypeId = 1
),
-- pick top-N interesting questions using windowing and ties handling
top_questions AS (
  SELECT *
  FROM (
    SELECT
      qs.*,
      ROW_NUMBER() OVER (ORDER BY qs.CompositeScore DESC, qs.BaseScore DESC, qs.ViewCount DESC) AS rn,
      NTILE(10) OVER (ORDER BY qs.CompositeScore DESC) AS Decile
    FROM question_scores qs
  ) t
  WHERE t.rn <= 250
)
-- final aggregation: join top questions with answers, users, tags, links and present complex fields
SELECT
  tq.QuestionId,
  LEFT(tq.Title,200) AS ShortTitle,
  tq.CompositeScore,
  tq.BaseScore,
  tq.ViewCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  tq.OwnerUserId,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation AS OwnerReputation,
  ARRAY_AGG(DISTINCT et.Tag ORDER BY et.Tag) FILTER (WHERE et.Tag IS NOT NULL) AS Tags,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = tq.QuestionId) AS RealAnswerCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 2) AS UpVotesOnQuestion,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 3) AS DownVotesOnQuestion,
  CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = tq.QuestionId AND pl.LinkTypeId = 3) THEN true ELSE false END AS HasDuplicateLinks,
  COALESCE(pls.OutgoingLinksCount,0) AS OutgoingLinksFromQuestion,
  COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId AND c.CreationDate > tq.CreationDate + interval '30 days'),0) AS CommentsAfter30Days,
  -- aggregate info about top 3 answers for this question (set operator like behavior via array aggregation)
  (SELECT json_agg(row_to_json(x)) FROM (
      SELECT a.Id AS AnswerId, a.Score AS AnswerScore, a.OwnerUserId AS AnswerOwner, ua2.DisplayName AS AnswerOwnerName,
             CASE WHEN tq.QuestionId = a.Id THEN false ELSE (a.Id = p.AcceptedAnswerId) END AS IsAcceptedByQuestion,
             LEFT(a.Body,140) AS Snippet
      FROM Posts a
      LEFT JOIN Posts p ON p.Id = tq.QuestionId
      LEFT JOIN Users ua2 ON ua2.Id = a.OwnerUserId
      WHERE a.ParentId = tq.QuestionId
      ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
      LIMIT 3
  ) x) AS Top3Answers,
  -- include correlated metrics: average score of answers where answer owner reputation > question owner reputation
  (SELECT AVG(a.Score) FROM Posts a LEFT JOIN Users ua3 ON ua3.Id = a.OwnerUserId WHERE a.ParentId = tq.QuestionId AND COALESCE(ua3.Reputation,0) > COALESCE(ua.Reputation,0)) AS AvgScore_Answers_By_HigherRepUsers,
  -- string expression and NULL logic: computed tag fingerprint
  (SELECT string_agg(tp.Tag || ':' || tp.PopularityRank::text, ',' ORDER BY tp.PopularityRank) FROM tag_popularity tp WHERE tp.Tag IN (SELECT et2.Tag FROM exploded_tags et2 WHERE et2.PostId = tq.QuestionId)) AS TagFingerprint,
  tq.Decile,
  now() AS ReportGeneratedAt
FROM top_questions tq
LEFT JOIN user_aggregates ua ON ua.UserId = tq.OwnerUserId
LEFT JOIN exploded_tags et ON et.PostId = tq.QuestionId
LEFT JOIN LATERAL (
  SELECT SUM(OutgoingLinksCount) AS OutgoingLinksCount FROM post_link_analysis pl2 WHERE pl2.PostId = tq.QuestionId
) pls ON true
GROUP BY tq.QuestionId, tq.Title, tq.CompositeScore, tq.BaseScore, tq.ViewCount, tq.AnswerCount, tq.FavoriteCount, tq.OwnerUserId, ua.DisplayName, ua.Reputation, pls.OutgoingLinksCount, tq.Decile
ORDER BY tq.CompositeScore DESC, tq.BaseScore DESC, tq.ViewCount DESC;