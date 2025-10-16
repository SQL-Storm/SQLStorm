-- {"query": "348.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14543} 
WITH RECURSIVE dup_clusters AS (
  SELECT pl.PostId AS start_post, pl.RelatedPostId AS clone_post, ARRAY[pl.PostId, pl.RelatedPostId] AS cluster
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  UNION
  SELECT dc.start_post, pl.RelatedPostId, dc.cluster || pl.RelatedPostId
  FROM dup_clusters dc
  JOIN PostLinks pl ON pl.PostId = dc.clone_post AND pl.LinkTypeId = 3
  WHERE NOT pl.RelatedPostId = ANY(dc.cluster)
),
tag_expanded AS (
  SELECT p.Id AS PostId,
         lower(trim(t.tg)) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(
      string_to_array(
        substring(p.Tags, 2, GREATEST(char_length(p.Tags) - 2, 0)),
        '><'
      )
    ) AS tg
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
q_base AS (
  SELECT q.Id,
         q.Title,
         q.Body,
         q.OwnerUserId,
         q.CreationDate,
         q.LastActivityDate,
         COALESCE(q.Score,0) AS QScore,
         COALESCE(q.ViewCount,0) AS QViews,
         q.AcceptedAnswerId,
         q.ClosedDate,
         q.Tags,
         regexp_replace(COALESCE(q.Body,''), '<[^>]+>', '', 'g') AS BodyText,
         (SELECT count(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS RealAnswerCount,
         (SELECT AVG(COALESCE(a.Score,0)) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
         (SELECT MAX(COALESCE(a.Score,0)) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS MaxAnswerScore,
         (SELECT count(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountQ,
         (SELECT count(*) FROM Votes v WHERE v.PostId = q.Id) AS VoteCountQ,
         (SELECT count(*) FROM PostHistory ph WHERE ph.PostId = q.Id) AS RevisionCount
  FROM Posts q
  WHERE q.PostTypeId = 1
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreation,
         u.Views AS UserViews,
         COALESCE((SELECT SUM(COALESCE(p.Score,0)) FROM Posts p WHERE p.OwnerUserId = u.Id),0) AS TotalPostScore,
         COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1),0) AS NumQuestions,
         COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2),0) AS NumAnswers,
         (SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) FROM Badges b WHERE b.UserId = u.Id) AS RecentBadges
  FROM Users u
),
tag_metrics AS (
  SELECT te.tag,
         count(distinct te.PostId) AS QuestionsWithTag,
         avg(qb.QScore) AS AvgScorePerTag,
         sum(qb.QViews) AS TotalViewsPerTag,
         count(distinct CASE WHEN qb.ClosedDate IS NOT NULL THEN te.PostId END) AS ClosedCount
  FROM tag_expanded te
  JOIN q_base qb ON qb.Id = te.PostId
  GROUP BY te.tag
),
top_by_views AS (
  SELECT 'views' AS bucket, qb.Id, qb.Title, qb.QScore, qb.QViews, qb.RealAnswerCount, qb.AvgAnswerScore
  FROM q_base qb
  ORDER BY qb.QViews DESC NULLS LAST
  LIMIT 100
),
top_by_score AS (
  SELECT 'score' AS bucket, qb.Id, qb.Title, qb.QScore, qb.QViews, qb.RealAnswerCount, qb.AvgAnswerScore
  FROM q_base qb
  ORDER BY qb.QScore DESC NULLS LAST
  LIMIT 100
),
top_candidates AS (
  SELECT * FROM top_by_views
  UNION ALL
  SELECT * FROM top_by_score
),
rank_windows AS (
  SELECT tc.*,
         row_number() OVER (PARTITION BY tc.bucket ORDER BY tc.QViews DESC NULLS LAST) AS rn_views_in_bucket,
         row_number() OVER (PARTITION BY tc.bucket ORDER BY tc.QScore DESC NULLS LAST) AS rn_score_in_bucket
  FROM top_candidates tc
),
detailed AS (
  SELECT rw.*,
         qb.BodyText,
         qb.OwnerUserId,
         u.DisplayName AS OwnerName,
         u.Reputation AS OwnerReputation,
         COALESCE(badges.BadgeCount,0) AS BadgeCount,
         tcg.tags_list,
         COALESCE((SELECT count(*) FROM Votes v WHERE v.PostId = rw.Id AND v.VoteTypeId = 2), 0) AS UpVotesCount,
         COALESCE((SELECT count(*) FROM Votes v WHERE v.PostId = rw.Id AND v.VoteTypeId = 3), 0) AS DownVotesCount,
         COALESCE((SELECT count(*) FROM Posts a WHERE a.ParentId = rw.Id), 0) AS AnswerCountComputed,
         (SELECT json_agg(json_build_object('a_id', a.Id, 'score', COALESCE(a.Score,0), 'owner', a.OwnerUserId))
          FROM Posts a WHERE a.ParentId = rw.Id ORDER BY a.Score DESC NULLS LAST LIMIT 5) AS TopFiveAnswers
  FROM rank_windows rw
  LEFT JOIN q_base qb ON qb.Id = rw.Id
  LEFT JOIN Users u ON u.Id = qb.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId
  ) badges ON badges.UserId = u.Id
  LEFT JOIN (
    SELECT te.PostId, STRING_AGG(te.tag, ', ' ORDER BY te.tag) AS tags_list
    FROM tag_expanded te
    GROUP BY te.PostId
  ) tcg ON tcg.PostId = rw.Id
),
popularity AS (
  SELECT
    d.*,
    (COALESCE(d.QScore,0) * 2.0
     + ln(GREATEST(COALESCE(d.QViews,0),1) + 1) * 1.5
     + COALESCE(d.RealAnswerCount,0) * 1.2
     + CASE WHEN COALESCE(d.OwnerReputation,0) = 0 THEN 0 ELSE COALESCE(d.OwnerReputation,0)::numeric / GREATEST(COALESCE(d.OwnerReputation,0),1) END
    ) AS RawPopularity,
    rank() OVER (ORDER BY (COALESCE(d.QScore,0) * 2.0
                           + ln(GREATEST(COALESCE(d.QViews,0),1) + 1) * 1.5
                           + COALESCE(d.RealAnswerCount,0) * 1.2
                           + CASE WHEN COALESCE(d.OwnerReputation,0) = 0 THEN 0 ELSE COALESCE(d.OwnerReputation,0)::numeric / GREATEST(COALESCE(d.OwnerReputation,0),1) END
                          ) DESC) AS PopularityRank
  FROM detailed d
),
final_selection AS (
  SELECT p.*,
         (SELECT AVG(COALESCE(score,0)) FROM Posts WHERE PostTypeId = 2 AND ParentId = p.Id AND Score IS NOT NULL) AS AvgAnsScoreCorrelated,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate - INTERVAL '30 days') AS RecentCommentCount,
         (SELECT count(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCountImportant,
         EXISTS (
           SELECT 1 FROM tag_expanded te
           JOIN Badges b ON lower(b.Name) = te.tag
           WHERE te.PostId = p.Id
         ) AS HasTagBadge
  FROM popularity p
),
main_list AS (
  SELECT
    fs.Id::int AS id,
    fs.Title::text AS title,
    fs.OwnerUserId::int AS owneruserid,
    fs.OwnerName::text AS ownername,
    fs.OwnerReputation::int AS ownerreputation,
    fs.QScore::int AS qscore,
    fs.QViews::int AS qviews,
    fs.RealAnswerCount::int AS answers,
    COALESCE(fs.AvgAnswerScore,0)::numeric AS avganswerscore,
    fs.tags_list::text AS tags,
    fs.UpVotesCount::int AS upvotes,
    fs.DownVotesCount::int AS downvotes,
    fs.PopularityRank::int AS popularityrank,
    fs.RawPopularity::numeric AS rawpopularity,
    fs.AvgAnsScoreCorrelated::numeric AS avgansscorecorrelated,
    fs.RecentCommentCount::int AS recentcommentcount,
    fs.EditCountImportant::int AS editcountimportant,
    fs.HasTagBadge::boolean AS hastagbadge,
    (CASE
       WHEN fs.ClosedDate IS NOT NULL THEN 'Closed on ' || to_char(fs.ClosedDate, 'YYYY-MM-DD')
       WHEN fs.AcceptedAnswerId IS NOT NULL THEN 'Has accepted answer (' || COALESCE((SELECT a.OwnerUserId::text FROM Posts a WHERE a.Id = fs.AcceptedAnswerId), 'unknown') || ')'
       ELSE 'Open'
     END)::text AS statesummary,
    substring(regexp_replace(COALESCE(fs.BodyText,''), '\s+', ' ', 'g') FROM 1 FOR 200) AS snippet,
    ('S:'||COALESCE(fs.QScore::text,'0')||' V:'||COALESCE(fs.QViews::text,'0')||' A:'||COALESCE(fs.RealAnswerCount::text,'0')||' P:'||lpad(COALESCE(fs.PopularityRank::text,'0'),4,'0')) AS compactsignature,
    fs.rn_views_in_bucket,
    fs.rn_score_in_bucket
  FROM final_selection fs
  WHERE (fs.PopularityRank <= 200 OR fs.rn_views_in_bucket <= 10 OR fs.rn_score_in_bucket <= 10)
    AND (fs.QViews IS NOT NULL OR fs.QScore IS NOT NULL)
  ORDER BY fs.PopularityRank NULLS LAST, fs.QViews DESC NULLS LAST
  LIMIT 250
),
tag_list AS (
  SELECT
    NULL::int AS id,
    ('TagSummary: '||tm.tag)::text AS title,
    NULL::int AS owneruserid,
    NULL::text AS ownername,
    NULL::int AS ownerreputation,
    COALESCE(ROUND(tm.AvgScorePerTag)::int,0) AS qscore,
    COALESCE(ROUND(tm.TotalViewsPerTag)::int,0) AS qviews,
    tm.QuestionsWithTag::int AS answers,
    NULL::numeric AS avganswerscore,
    tm.tag::text AS tags,
    0::int AS upvotes,
    0::int AS downvotes,
    dense_rank() OVER (ORDER BY tm.AvgScorePerTag DESC)::int AS popularityrank,
    tm.AvgScorePerTag::numeric AS rawpopularity,
    NULL::numeric AS avgansscorecorrelated,
    NULL::int AS recentcommentcount,
    tm.ClosedCount::int AS editcountimportant,
    (SELECT COALESCE(bool_or(TagBased), false) FROM Badges WHERE lower(Name)=tm.tag)::boolean AS hastagbadge,
    ('Tag: '||tm.tag)::text AS statesummary,
    NULL::text AS snippet,
    tm.tag::text AS compactsignature,
    NULL::int AS rn_views_in_bucket,
    NULL::int AS rn_score_in_bucket
  FROM tag_metrics tm
  WHERE tm.QuestionsWithTag > 20
  ORDER BY tm.AvgScorePerTag DESC
  LIMIT 50
),
excluded_list AS (
  SELECT
    NULL::int AS id,
    ('TagSummary: '||t.tag)::text AS title,
    NULL::int AS owneruserid,
    NULL::text AS ownername,
    NULL::int AS ownerreputation,
    0::int AS qscore,
    0::int AS qviews,
    0::int AS answers,
    NULL::numeric AS avganswerscore,
    t.tag::text AS tags,
    0::int AS upvotes,
    0::int AS downvotes,
    9999::int AS popularityrank,
    0::numeric AS rawpopularity,
    NULL::numeric AS avgansscorecorrelated,
    NULL::int AS recentcommentcount,
    0::int AS editcountimportant,
    false::boolean AS hastagbadge,
    'Excluded'::text AS statesummary,
    NULL::text AS snippet,
    t.tag::text AS compactsignature,
    NULL::int AS rn_views_in_bucket,
    NULL::int AS rn_score_in_bucket
  FROM (SELECT tag, QuestionsWithTag FROM tag_metrics ORDER BY QuestionsWithTag DESC LIMIT 10) t
)
SELECT id, title, owneruserid, ownername, ownerreputation, qscore, qviews, answers, avganswerscore, tags, upvotes, downvotes, popularityrank, rawpopularity, avgansscorecorrelated, recentcommentcount, editcountimportant, hastagbadge, statesummary, snippet, compactsignature
FROM main_list
UNION ALL
SELECT id, title, owneruserid, ownername, ownerreputation, qscore, qviews, answers, avganswerscore, tags, upvotes, downvotes, popularityrank, rawpopularity, avgansscorecorrelated, recentcommentcount, editcountimportant, hastagbadge, statesummary, snippet, compactsignature
FROM tag_list
EXCEPT
SELECT id, title, owneruserid, ownername, ownerreputation, qscore, qviews, answers, avganswerscore, tags, upvotes, downvotes, popularityrank, rawpopularity, avgansscorecorrelated, recentcommentcount, editcountimportant, hastagbadge, statesummary, snippet, compactsignature
FROM excluded_list;