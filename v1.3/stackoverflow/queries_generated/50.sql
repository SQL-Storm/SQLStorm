-- {"query": "50.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2566} 
with
-- top contributors by answer score velocity in last year
year_answers as (
  select p.OwnerUserId as UserId,
         p.Id as AnswerId,
         p.ParentId as QuestionId,
         p.CreationDate,
         p.Score,
         row_number() over (partition by p.OwnerUserId order by p.CreationDate desc, p.Score desc) as rn
  from Posts p
  where p.PostTypeId = 2
    and p.OwnerUserId is not null
    and p.CreationDate >= now() - interval '365 days'
),
top_recent_answers as (
  select * from year_answers where rn <= 50
),

-- compute question lifecycles with accepted answers and response lag
question_lifecycle as (
  select q.Id as QuestionId,
         q.CreationDate as QCreated,
         q.AcceptedAnswerId,
         a.Id as AcceptedId,
         a.CreationDate as ACreated,
         coalesce(extract(epoch from (a.CreationDate - q.CreationDate))/3600.0, null) as HoursToAccept,
         q.Score as QScore,
         q.ViewCount,
         q.Tags
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
),

-- tag exploded to rows (Post Tags are stored like "<tag1><tag2>")
exploded_tags as (
  select p.Id as QuestionId,
         trim(both '<>' from elem) as Tag
  from Posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,'') from 2 for greatest(length(coalesce(p.Tags,''))-2,0)), '><')) as elem
  ) s
  where p.PostTypeId = 1
    and p.Tags is not null
),

-- user badge aggregation including first/last badge dates and tag-based count
user_badges as (
  select b.UserId,
         count(*) as TotalBadges,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
         sum(case when b.TagBased = cast(1 as bit) then 1 else 0 end) as TagBasedCount,
         min(b.Date) as FirstBadgeDate,
         max(b.Date) as LastBadgeDate,
         bool_or(b.TagBased = cast(1 as bit)) as HasAnyTagBadges
  from Badges b
  group by b.UserId
),

-- votes summary per post including correlated subquery for distinct voter count and window to rank posts per owner
votes_summary as (
  select p.Id as PostId,
         p.OwnerUserId,
         p.PostTypeId,
         p.Score as BaseScore,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as NetVotes,
         count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesCount,
         count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesCount,
         (select count(distinct vv.UserId) from Votes vv where vv.PostId = p.Id and vv.UserId is not null) as DistinctVoters,
         row_number() over (partition by p.OwnerUserId order by coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) desc nulls last) as OwnerRankByVotes
  from Posts p
  left join Votes v on v.PostId = p.Id
  where p.PostTypeId in (1,2)
  group by p.Id, p.OwnerUserId, p.PostTypeId, p.Score
),

-- posts with heavy null & string logic and complex predicate to find "controversial" posts
controversial_posts as (
  select p.Id,
         p.Title,
         p.Body,
         p.Tags,
         p.OwnerUserId,
         p.Score,
         p.CreationDate,
         vs.UpVotesCount,
         vs.DownVotesCount,
         vs.DistinctVoters,
         case
           when vs.UpVotesCount + vs.DownVotesCount = 0 then null
           else round(100.0 * vs.DownVotesCount / greatest(1.0, (vs.UpVotesCount + vs.DownVotesCount)),2)
         end as DownPercent,
         (p.Score - coalesce(vs.NetVotes,0)) as ScoreVsNetVoteDiff,
         -- fuzzy title hash for grouping (simple: length + vowels count)
         length(coalesce(p.Title,'')) * (regexp_count(coalesce(p.Title,''), '[aeiouAEIOU]') + 1) as TitleFuzzy
  from Posts p
  left join votes_summary vs on vs.PostId = p.Id
  where p.PostTypeId in (1,2)
    and (vs.DownVotesCount >= 3 or (p.Score < 0 and coalesce(vs.DownVotesCount,0) >= 1))
),

-- assemble candidate users from multiple signals
candidate_users as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         u.UpVotes as UserUpVotes,
         u.DownVotes as UserDownVotes,
         ub.TotalBadges,
         ub.GoldCount,
         ub.SilverCount,
         ub.BronzeCount,
         ub.HasAnyTagBadges
  from Users u
  left join user_badges ub on ub.UserId = u.Id
  where u.Reputation >= 1000
     or ub.TotalBadges >= 5
     or u.Views >= 10000
),

-- correlate top recent answers to question lifecycle and tags and controversial flags
answer_enrichment as (
  select a.AnswerId,
         a.UserId,
         a.QuestionId,
         ql.QCreated,
         ql.ACreated,
         ql.HoursToAccept,
         ql.Tags,
         et.Tag,
         vs.NetVotes,
         vs.UpVotesCount,
         vs.DownVotesCount,
         cp.DownPercent,
         cu.DisplayName as AnswererName,
         cu.Reputation as AnswererRep,
         row_number() over (partition by a.AnswerId order by vs.NetVotes desc nulls last, vs.UpVotesCount desc) as rnk
  from top_recent_answers a
  left join question_lifecycle ql on ql.QuestionId = a.QuestionId
  left join exploded_tags et on et.QuestionId = a.QuestionId
  left join votes_summary vs on vs.PostId = a.AnswerId
  left join controversial_posts cp on cp.Id = a.AnswerId
  left join Users cu on cu.Id = a.UserId
),

-- aggregate tag-level metrics including moving averages via window funcs
tag_metrics as (
  select et.Tag,
         count(distinct p.Id) as QuestionCount,
         sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAccepted,
         avg(coalesce(p.Score,0)) as AvgQuestionScore,
         percentile_disc(0.5) within group (order by coalesce(p.Score,0)) as MedianQuestionScore,
         sum(case when exists (select 1 from Posts a where a.ParentId = p.Id and a.Score >= 5) then 1 else 0 end) as QuestionsWithHighScoreAnswer,
         -- moving window of recent activity (past 90 days)
         sum(case when p.CreationDate >= now() - interval '90 days' then 1 else 0 end) as RecentQuestions90d,
         sum(case when p.CreationDate >= now() - interval '30 days' then 1 else 0 end) as RecentQuestions30d,
         rank() over (order by count(distinct p.Id) desc) as PopularityRank
  from exploded_tags et
  join Posts p on p.Id = et.QuestionId
  where p.PostTypeId = 1
  group by et.Tag
),

-- final selection mixing everything with set operators to produce varied rows
final_selection as (
  select
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.TotalBadges,
    tm.Tag as FocusTag,
    tm.QuestionCount,
    tm.RecentQuestions30d,
    ae.AnswerId,
    ae.QuestionId,
    ae.Tag as AnswerTag,
    ae.NetVotes,
    ae.UpVotesCount,
    ae.DownVotesCount,
    ae.HoursToAccept,
    cp.DownPercent as AnswerDownPercent,
    vs.OwnerRankByVotes,
    -- composite score (arbitrary heavy expression)
    (coalesce(ae.NetVotes,0) * 2.7 + coalesce(tm.QuestionCount,0) * 0.3 + coalesce(cu.Reputation,0)/1000.0 * 1.5
      - least(coalesce(ae.DownVotesCount,0),10) * 0.8
      + case when cu.HasAnyTagBadges then 5 else 0 end
      + (case when ae.HoursToAccept is null then 0 else greatest(0, 48 - ae.HoursToAccept)/48 end)
    ) as CompositeScore
  from candidate_users cu
  left join tag_metrics tm on tm.Tag in (
      select Tag from exploded_tags where QuestionId in (
        select Id from Posts where OwnerUserId = cu.UserId and PostTypeId = 1 limit 5
      )
    )
  left join answer_enrichment ae on ae.UserId = cu.UserId and ae.rnk = 1
  left join votes_summary vs on vs.PostId = ae.AnswerId
  left join controversial_posts cp on cp.Id = ae.AnswerId
)

-- produce unioned rows: top composite scorers, random sample of controversial posts, and tag leaders
select 'TopUsersByComposite' as RowKind, fs.* from (
  select * from final_selection
  order by CompositeScore desc nulls last
  limit 50
) fs

union all

select 'ControversialSample' as RowKind, 
       null::int as UserId, null::varchar as DisplayName, null::int as Reputation, null::int as TotalBadges,
       cp.Tag as FocusTag, null::int as QuestionCount, null::int as RecentQuestions30d,
       cp.Id as AnswerId, null::int as QuestionId, null::varchar as AnswerTag,
       cp.NetVotes, cp.UpVotesCount, cp.DownVotesCount, null::float as HoursToAccept,
       cp.DownPercent as AnswerDownPercent, null::int as OwnerRankByVotes, 
       (coalesce(cp.NetVotes,0)*1.2 - coalesce(cp.DownVotesCount,0)*0.9) as CompositeScore
from controversial_posts cp
left join exploded_tags et on et.QuestionId = cp.Id
order by cp.DownPercent desc nulls last
limit 25

union

select 'TagLeaders' as RowKind, 
       null::int as UserId, null::varchar as DisplayName, null::int as Reputation, null::int as TotalBadges,
       tm.Tag as FocusTag, tm.QuestionCount, tm.RecentQuestions30d,
       null::int as AnswerId, null::int as QuestionId, null::varchar as AnswerTag,
       null::int as NetVotes, null::int as UpVotesCount, null::int as DownVotesCount, null::float as HoursToAccept,
       null::float as AnswerDownPercent, null::int as OwnerRankByVotes,
       (tm.QuestionCount * 0.5 + tm.RecentQuestions30d * 2) as CompositeScore
from tag_metrics tm
order by tm.QuestionCount desc nulls last
limit 25;