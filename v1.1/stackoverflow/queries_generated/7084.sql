-- {"query": "7084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2220} 
with
-- heavy tag explosion: explode Tags into rows for questions
QuestionTags as (
  select p.Id as QuestionId,
         lower(trim(regexp_replace(tag, '[^a-z0-9+#-]', '', 'gi'))) as Tag
  from Posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><')) as tag
  ) t
  where p.PostTypeId = 1
),
-- compute user metrics: lifetime windows and recent activity
UserActivity as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsPosted,
         count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersPosted,
         sum(coalesce(p.Score,0)) as PostScoreSum,
         max(p.CreationDate) as MostRecentPost,
         percentile_cont(0.5) within group (order by coalesce(p.Score,0)) over (partition by u.Id) as MedianPostScore
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- identify hot tags per user by counting answers to questions having tag
UserTagAffinity as (
  select ua.UserId, qt.Tag,
         count(a.Id) as AnswersToTagQuestions,
         rank() over (partition by ua.UserId order by count(a.Id) desc) as Rk
  from UserActivity ua
  join Posts a on a.OwnerUserId = ua.UserId and a.PostTypeId = 2
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  join QuestionTags qt on qt.QuestionId = q.Id
  group by ua.UserId, qt.Tag
),
TopUserTags as (
  select UserId, Tag, AnswersToTagQuestions
  from UserTagAffinity
  where Rk <= 3
),
-- compute answer velocity and acceptance dynamics per question
AnswerDynamics as (
  select q.Id as QuestionId,
         q.CreationDate as QuestionCreated,
         q.AcceptedAnswerId,
         count(a.Id) as TotalAnswers,
         min(a.CreationDate) as FirstAnswerAt,
         max(a.CreationDate) as LastAnswerAt,
         avg(extract(epoch from (a.CreationDate - q.CreationDate))) as AvgAnswerSeconds,
         sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedCount
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id, q.CreationDate, q.AcceptedAnswerId
),
-- gather vote context by join and windowing (e.g., recent upvotes pace)
PostVotePace as (
  select v.PostId,
         sum(case when vt.Name ilike 'up%' then 1 else 0 end) as UpVotes,
         sum(case when vt.Name ilike 'down%' then 1 else 0 end) as DownVotes,
         count(*) as TotalVotes,
         min(v.CreationDate) as FirstVote,
         max(v.CreationDate) as LastVote,
         case when max(v.CreationDate) is null then null
              else extract(epoch from (max(v.CreationDate)-min(v.CreationDate)))/greatest(count(*)-1,1) end as SecsPerVote
  from Votes v
  left join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
-- tag-level aggregates for a complex tag score
TagAggregates as (
  select qt.Tag,
         count(distinct q.Id) as QuestionCount,
         avg(coalesce(q.ViewCount,0)) as AvgViews,
         avg(coalesce(q.Score,0)) as AvgScore,
         sum(case when q.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedRateRaw,
         sum(coalesce(pvp.UpVotes,0)) as TagUpVotes
  from QuestionTags qt
  join Posts q on q.Id = qt.QuestionId
  left join PostVotePace pvp on pvp.PostId = q.Id
  group by qt.Tag
),
-- compute a complexity metric per question combining many signals and null-safe logic
QuestionComplexity as (
  select q.Id as QuestionId,
         q.Title,
         q.Tags,
         q.OwnerUserId,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         coalesce(ad.TotalAnswers,0) as TotalAnswers,
         coalesce(ad.AvgAnswerSeconds, 1e9) as AvgAnswerSeconds,
         coalesce(pvp.UpVotes,0) as UpVotes,
         coalesce(pvp.DownVotes,0) as DownVotes,
         coalesce(ta.AvgScore,0) as TagAvgScore,
         coalesce(ta.AvgViews,0) as TagAvgViews,
         -- complexity uses log, null-safe arithmetic, string parsing and boolean weightings
         ( 0.4 * log(greatest(coalesce(q.ViewCount,0),1) + 1)
         + 0.3 * ln(greatest(abs(coalesce(q.Score,0)) ,1) + 1)
         + 0.2 * (case when coalesce(q.AcceptedAnswerId,0) = 0 then 1 else 0 end)
         + 0.15 * (1.0 / (1 + least(coalesce(ad.AvgAnswerSeconds,1e9)/86400.0, 3650))) -- faster answers reduce complexity
         + 0.25 * (least(coalesce(q.AnswerCount,0),10) / 10.0)
         + 0.1 * (coalesce(pvp.DownVotes,0) / greatest(nullif(pvp.UpVotes + pvp.DownVotes,0),1))
         + 0.05 * (coalesce(ta.AvgScore,0) / greatest(ta.AvgScore + 1,1))
         ) * (1 + greatest(coalesce(q.CommentCount,0),0)/10.0) as ComplexityScore
  from Posts q
  left join AnswerDynamics ad on ad.QuestionId = q.Id
  left join PostVotePace pvp on pvp.PostId = q.Id
  left join TagAggregates ta on ta.Tag = (select lower(trim(regexp_replace(unnest(string_to_array(substring(coalesce(q.Tags,''),2,length(coalesce(q.Tags,''))-2),'><')),'[^a-z0-9+#-]','','gi'))) from generate_series(1,1)) -- pick first tag normalized
  where q.PostTypeId = 1
),
-- rank questions by complexity and include correlated subquery to fetch top answerer info
TopComplexQuestions as (
  select qc.*,
         row_number() over (order by qc.ComplexityScore desc nulls last, qc.ViewCount desc nulls last) as ComplexRank,
         -- correlated: find user with most answers to this question (rare, but example) or top answer score
         (
           select u.DisplayName || coalesce(' (rep='||u.Reputation||')','')
           from Posts a
           join Users u on u.Id = a.OwnerUserId
           where a.ParentId = qc.QuestionId and a.PostTypeId = 2
           order by a.Score desc nulls last, a.CreationDate asc
           limit 1
         ) as TopAnswerer,
         (
           select string_agg(distinct t.Tag, ',') from QuestionTags t where t.QuestionId = qc.QuestionId
         ) as TagList
  from QuestionComplexity qc
),
-- assemble final diagnostics per user combining their top tags and median score with existence checks
UserDiagnostics as (
  select ua.UserId,
         ua.Reputation,
         ua.QuestionsPosted,
         ua.AnswersPosted,
         ua.MedianPostScore,
         coalesce(tt.Tag,'<none>') as TopTag,
         coalesce(tt.AnswersToTagQuestions,0) as TopTagAnswers,
         row_number() over (partition by ua.UserId order by coalesce(tt.AnswersToTagQuestions,0) desc) as TagRank
  from UserActivity ua
  left join TopUserTags tt on tt.UserId = ua.UserId
)
select
  tc.ComplexRank,
  tc.QuestionId,
  left(coalesce(tc.Title,'<no title>'),120) as TitleSnippet,
  coalesce(tc.ViewCount,0) as Views,
  coalesce(tc.Score,0) as Score,
  tc.AnswerCount,
  round(tc.ComplexityScore::numeric,4) as ComplexityScore,
  tc.TopAnswerer,
  tc.TagList,
  ua.UserId as OwnerUserId,
  ua.Reputation as OwnerReputation,
  ua.QuestionsPosted,
  ua.AnswersPosted,
  ua.MedianPostScore,
  ud.TopTag as OwnerTopTag,
  ud.TopTagAnswers,
  -- cross-check: how many badges for owner in last year and golden/silver/bronze split using conditional aggregation with null-safe dates
  b.BadgesLastYear,
  b.GoldBadges,
  b.SilverBadges,
  b.BronzeBadges
from TopComplexQuestions tc
left join Posts p on p.Id = tc.QuestionId
left join Users ua on ua.Id = p.OwnerUserId
left join UserDiagnostics ud on ud.UserId = ua.Id and ud.TagRank = 1
left join (
  select b.UserId,
         count(*) filter (where b.Date >= now() - interval '365 days') as BadgesLastYear,
         count(*) filter (where b.Class = 1) as GoldBadges,
         count(*) filter (where b.Class = 2) as SilverBadges,
         count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId
) b on b.UserId = ua.Id
where tc.ComplexRank <= 250
order by tc.ComplexRank asc, tc.ComplexityScore desc;