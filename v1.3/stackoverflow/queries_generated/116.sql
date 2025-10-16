-- {"query": "116.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2651} 
with
-- basic question set
questions as (
  select p.*,
         u.DisplayName as OwnerName,
         coalesce(p.Tags,'') as RawTags,
         -- extract tags into array (schema hint provided)
         string_to_array(substring(coalesce(p.Tags,''), 2, length(coalesce(p.Tags,''))-2), '><') as TagArray
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId = 1
),
-- explode tags for tag-level analysis
question_tags as (
  select q.Id as QuestionId,
         unnest(q.TagArray) as Tag
  from questions q
),
-- aggregate votes for posts (questions + answers)
post_votes as (
  select v.PostId,
         count(*) filter (where v.VoteTypeId = 2) as UpVotes,
         count(*) filter (where v.VoteTypeId = 3) as DownVotes,
         count(*) filter (where v.VoteTypeId = 5) as Favorites,
         sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted
  from Votes v
  group by v.PostId
),
-- answers with metrics and windowed ranks per question
answers as (
  select a.*,
         av.UpVotes as AnswerUpVotes,
         av.DownVotes as AnswerDownVotes,
         u.DisplayName as AnswererName,
         -- time delta from question creation to answer creation (seconds)
         extract(epoch from (a.CreationDate - q.CreationDate)) as SecondsAfterQuestion,
         row_number() over (partition by a.ParentId order by coalesce(av.UpVotes,0) desc, a.Score desc, a.CreationDate asc) as TopByVotesRank,
         rank() over (partition by a.ParentId order by a.Score desc nulls last) as ScoreRank
  from Posts a
  join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
  left join post_votes av on av.PostId = a.Id
  left join Users u on a.OwnerUserId = u.Id
  where a.PostTypeId = 2
),
-- compute per-question aggregated answer stats
question_answer_stats as (
  select q.Id as QuestionId,
         count(a.Id) as AnswerCountComputed,
         sum(coalesce(a.Score,0)) as AnswersTotalScore,
         avg(coalesce(a.Score,0)) as AnswersAvgScore,
         max(coalesce(av.UpVotes,0)) as MaxAnswerUpVotes,
         -- identify top answerer (by upvotes, tie-break by earliest)
         (select u.DisplayName
          from Posts aa
          left join post_votes av2 on av2.PostId = aa.Id
          left join Users u on aa.OwnerUserId = u.Id
          where aa.ParentId = q.Id and aa.PostTypeId = 2
          order by coalesce(av2.UpVotes,0) desc, aa.CreationDate asc
          limit 1) as TopAnswererName,
         -- time to accepted answer (seconds) if exists
         case
           when q.AcceptedAnswerId is not null then
             extract(epoch from (
               (select a2.CreationDate from Posts a2 where a2.Id = q.AcceptedAnswerId)
               - q.CreationDate
             ))
           else null
         end as SecondsToAccepted
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join post_votes av on av.PostId = a.Id
  where q.PostTypeId = 1
  group by q.Id, q.AcceptedAnswerId
),
-- recent edits & history complexity indicator (correlated subquery)
question_history_stats as (
  select q.Id as QuestionId,
         (select count(*) from PostHistory ph where ph.PostId = q.Id) as HistoryCount,
         max(ph.CreationDate) as LastHistoryDate
  from questions q
  left join PostHistory ph on ph.PostId = q.Id
  group by q.Id
),
-- badge counts for owners
owner_badges as (
  select b.UserId,
         count(*) filter (where b.Class = 1) as GoldBadges,
         count(*) filter (where b.Class = 2) as SilverBadges,
         count(*) filter (where b.Class = 3) as BronzeBadges,
         count(*) as TotalBadges
  from Badges b
  group by b.UserId
),
-- duplicates/links metrics (exists correlated)
question_link_agg as (
  select q.Id as QuestionId,
         count(pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateLinksOut, -- posts q is duplicate of
         count(pl.Id) filter (where pl.LinkTypeId = 1) as LinkedOut,
         exists (
           select 1 from PostLinks pl2 where pl2.PostId = q.Id and pl2.LinkTypeId = 3
         ) as HasDuplicateFlag
  from questions q
  left join PostLinks pl on pl.PostId = q.Id
  group by q.Id
),
-- combine all per-question info
question_enriched as (
  select q.*,
         qa.AnswerCountComputed,
         qa.AnswersTotalScore,
         qa.AnswersAvgScore,
         qa.MaxAnswerUpVotes,
         qa.TopAnswererName,
         qa.SecondsToAccepted,
         coalesce(qs.HistoryCount,0) as HistoryCount,
         qs.LastHistoryDate,
         coalesce(ob.GoldBadges,0) as OwnerGold,
         coalesce(ob.SilverBadges,0) as OwnerSilver,
         coalesce(ob.BronzeBadges,0) as OwnerBronze,
         coalesce(ql.DuplicateLinksOut,0) as DuplicateLinksOut,
         coalesce(ql.LinkedOut,0) as LinkedOut,
         ql.HasDuplicateFlag
  from questions q
  left join question_answer_stats qa on qa.QuestionId = q.Id
  left join question_history_stats qs on qs.QuestionId = q.Id
  left join owner_badges ob on ob.UserId = q.OwnerUserId
  left join question_link_agg ql on ql.QuestionId = q.Id
),
-- windowed trends: tag popularity and trending score
tag_trends as (
  select qt.Tag,
         count(distinct qt.QuestionId) as QuestionCount,
         sum(coalesce(p.Score,0)) as TagScoreSum,
         avg(coalesce(p.ViewCount,0)) as AvgViews,
         row_number() over (order by count(distinct qt.QuestionId) desc) as TagPopularityRank
  from question_tags qt
  join Posts p on p.Id = qt.QuestionId
  group by qt.Tag
),
-- union sets: questions with accepted answers vs without, to test set ops
questions_with_accepted as (
  select qe.* from question_enriched qe where qe.AcceptedAnswerId is not null
),
questions_without_accepted as (
  select qe.* from question_enriched qe where qe.AcceptedAnswerId is null
),
combined_set as (
  select 'with_accepted' as cohort, q.* from questions_with_accepted q
  union all
  select 'without_accepted' as cohort, q.* from questions_without_accepted q
)
-- final selection with complex predicates, joins, windowing and string expressions
select
  cs.cohort,
  cs.Id as QuestionId,
  left(coalesce(cs.Title,''),120) as ShortTitle,
  coalesce(cs.OwnerName,'<anon>') as OwnerName,
  cs.OwnerUserId,
  coalesce(cs.AnswerCountComputed,0) as AnswerCountComputed,
  coalesce(cs.AnswersAvgScore,0)::numeric(10,2) as AnswersAvgScore,
  coalesce(cs.SecondsToAccepted,null) as SecondsToAccepted,
  -- classify speed to accepted into buckets with null handling
  case
    when cs.SecondsToAccepted is null then 'no_accept'
    when cs.SecondsToAccepted < 3600 then 'fast(<1h)'
    when cs.SecondsToAccepted < 86400 then 'moderate(<1d)'
    else 'slow(>=1d)'
  end as AcceptSpeed,
  cs.HistoryCount,
  -- compute owner's veteran score
  (coalesce(cs.OwnerGold,0)*10 + coalesce(cs.OwnerSilver,0)*3 + coalesce(cs.OwnerBronze,0)*1 + greatest(coalesce(u.Reputation,0)/100,0)) as OwnerVeteranScore,
  -- tag list reconstructed and trimmed
  coalesce(array_to_string(cs.TagArray,', '),'') as TagList,
  -- detect if likely duplicate via heuristics
  case
    when cs.HasDuplicateFlag then true
    when cs.DuplicateLinksOut > 0 then true
    when cs.AnswerCountComputed = 0 and cs.HistoryCount > 5 then true
    else false
  end as LikelyDuplicate,
  -- string heavy expression: normalized title fingerprint (lower, remove non-word, collapse spaces)
  regexp_replace(lower(coalesce(cs.Title,'')), '\W+', ' ', 'g') as TitleFingerprint,
  -- windowed ranking: popularity within cohort by viewcount then score
  dense_rank() over (partition by cs.cohort order by coalesce(cs.ViewCount,0) desc, coalesce(cs.Score,0) desc) as PopularityRankInCohort,
  -- correlated subquery: count of distinct answerers for question
  (select count(distinct a.OwnerUserId) from Posts a where a.ParentId = cs.Id and a.PostTypeId = 2 and a.OwnerUserId is not null) as DistinctAnswerers,
  -- correlated subquery: count of recent comments on the question (last 30 days)
  (select count(*) from Comments c where c.PostId = cs.Id and c.CreationDate >= now() - interval '30 days') as RecentCommentCount,
  -- boolean heavy predicate with NULL logic: active recently?
  case
    when cs.LastHistoryDate is not null and cs.LastHistoryDate >= now() - interval '90 days' then true
    when cs.LastActivityDate is not null and cs.LastActivityDate >= now() - interval '90 days' then true
    else false
  end as ActiveIn90Days,
  -- join to tag trends for primary tag (first tag) using left join and null fallback
  tt.Tag as PrimaryTag,
  tt.QuestionCount as PrimaryTagQuestionCount,
  tt.TagPopularityRank as PrimaryTagRank
from combined_set cs
left join tag_trends tt on tt.Tag = (case when array_length(cs.TagArray,1) >= 1 then cs.TagArray[1] else null end)
left join Users u on u.Id = cs.OwnerUserId
where
  -- complicated predicate: prefer questions with at least one answer or high viewcount or recent activity, test NULL logic
  (
    coalesce(cs.AnswerCountComputed,0) > 0
    or coalesce(cs.ViewCount,0) > 1000
    or cs.LastActivityDate >= now() - interval '30 days'
  )
  -- exclude extremely old low-activity posts unless they have badges
  and not (
    cs.LastActivityDate < now() - interval '365 days'
    and coalesce(cs.TotalBadges,0) = 0
  )
order by cs.cohort, PopularityRankInCohort, cs.Id
limit 200;