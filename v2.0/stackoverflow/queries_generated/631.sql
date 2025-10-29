-- {"query": "631.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3322} 
with
q_posts as (
  select p.Id as QuestionId,
         p.CreationDate as QCreationDate,
         p.Title,
         p.Tags,
         p.OwnerUserId as QOwnerId,
         p.Score as QScore,
         p.ViewCount,
         p.AcceptedAnswerId,
         coalesce(p.AnswerCount, 0) as AnswerCount,
         case when p.ClosedDate is not null then 1 else 0 end as IsClosed
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AOwnerId,
         a.Score as AScore,
         a.CreationDate as ACreationDate
  from Posts a
  where a.PostTypeId = 2
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         u.CreationDate as UCreationDate,
         coalesce(nullif(trim(coalesce(u.Location,'')),''), 'Unknown') as NormLocation,
         date_part('year', age(current_timestamp, u.CreationDate))::int as AccountAgeYears
  from Users u
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvoteCnt,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvoteCnt,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCnt,
         sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
         sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
         min(v.CreationDate) as FirstVoteAt,
         max(v.CreationDate) as LastVoteAt
  from Votes v
  group by v.PostId
),
comment_agg as (
  select c.PostId,
         count(*) as CommentCnt,
         sum(case when c.Score > 0 then 1 else 0 end) as PosComments,
         max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
tag_expand as (
  select p.Id as PostId,
         unnest(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><')) as TagName
  from Posts p
  where p.PostTypeId = 1 and p.Tags is not null
),
tag_rank as (
  select te.PostId,
         te.TagName,
         t.Count as TagGlobalCount,
         row_number() over (partition by te.PostId order by t.Count desc nulls last, te.TagName) as TagRankByGlobal
  from tag_expand te
  left join Tags t on lower(t.TagName) = lower(te.TagName)
),
best_tag as (
  select PostId,
         TagName as DominantTag,
         TagGlobalCount
  from tag_rank
  where TagRankByGlobal = 1
),
edits as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCnt,
         max(ph.CreationDate) as LastEditAt,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVoteEvents,
         count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
         sum(case when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+' then 1 else 0 end) as CloseReasonsLogged
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select pl.PostId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
         min(pl.CreationDate) as FirstLinkAt
  from PostLinks pl
  group by pl.PostId
),
accepted_answer as (
  select a.QuestionId,
         a.AnswerId as AcceptedAnswerId,
         a.AOwnerId as AcceptedOwnerId,
         a.AScore as AcceptedScore,
         a.ACreationDate as AcceptedAt
  from a_posts a
  join q_posts q on q.AcceptedAnswerId = a.AnswerId
),
answerers as (
  select a.QuestionId,
         count(*) as AnswererCnt,
         count(distinct a.AOwnerId) as DistinctAnswerers,
         max(a.AScore) as MaxAnswerScore,
         min(a.ACreationDate) as FirstAnswerAt
  from a_posts a
  group by a.QuestionId
),
q_activity as (
  select q.QuestionId,
         q.QCreationDate,
         greatest(
           coalesce(q.QCreationDate, timestamp 'epoch'),
           coalesce(v.FirstVoteAt, timestamp 'epoch'),
           coalesce(v.LastVoteAt, timestamp 'epoch'),
           coalesce(c.LastCommentAt, timestamp 'epoch'),
           coalesce(e.LastEditAt, timestamp 'epoch')
         ) as LastActivityDerived
  from q_posts q
  left join votes_agg v on v.PostId = q.QuestionId
  left join comment_agg c on c.PostId = q.QuestionId
  left join edits e on e.PostId = q.QuestionId
),
owner_enriched as (
  select q.QuestionId,
         u.UserId as QOwnerId,
         u.Reputation as OwnerReputation,
         u.AccountAgeYears,
         u.NormLocation,
         (u.UpVotes - u.DownVotes) as OwnerNetVotes,
         case when u.ProfileViews is null or u.ProfileViews = 0 then null else (u.Reputation::numeric / nullif(u.ProfileViews,0)) end as RepPerProfileView
  from q_posts q
  left join user_stats u on u.UserId = q.QOwnerId
),
rankings as (
  select
    q.QuestionId,
    q.QScore,
    q.ViewCount,
    a.AnswererCnt,
    coalesce(v.UpvoteCnt,0) as UpvoteCnt,
    coalesce(v.DownvoteCnt,0) as DownvoteCnt,
    coalesce(v.FavoriteCnt,0) as FavoriteCnt,
    coalesce(v.BountyStarted,0) as BountyStarted,
    coalesce(v.BountyAwarded,0) as BountyAwarded,
    coalesce(c.CommentCnt,0) as CommentCnt,
    coalesce(e.EditCnt,0) as EditCnt,
    coalesce(d.DuplicateLinks,0) as DuplicateLinks,
    coalesce(d.LinkedLinks,0) as LinkedLinks,
    dense_rank() over (order by q.QScore desc nulls last, coalesce(v.UpvoteCnt,0) desc, coalesce(v.FavoriteCnt,0) desc) as RankByScore,
    dense_rank() over (order by coalesce(v.FavoriteCnt,0) desc, q.ViewCount desc nulls last) as RankByFav,
    dense_rank() over (order by (coalesce(v.UpvoteCnt,0) - coalesce(v.DownvoteCnt,0)) desc) as RankByNetVotes,
    ntile(100) over (order by q.ViewCount desc nulls last) as ViewPercentile
  from q_posts q
  left join votes_agg v on v.PostId = q.QuestionId
  left join comment_agg c on c.PostId = q.QuestionId
  left join edits e on e.PostId = q.QuestionId
  left join dup_links d on d.PostId = q.QuestionId
  left join answerers a on a.QuestionId = q.QuestionId
),
quality_flags as (
  select
    r.QuestionId,
    case when r.QScore >= 10 and r.ViewCount >= 1000 and r.FavoriteCnt >= 5 then 1 else 0 end as IsPopular,
    case when r.EditCnt >= 5 or r.CommentCnt >= 20 then 1 else 0 end as IsContentious,
    case when r.DuplicateLinks > 0 then 1 else 0 end as IsDuplicateLinked,
    case when r.BountyAwarded > 0 then 1 else 0 end as HasBountyHistory,
    case when r.ViewPercentile >= 95 then 1 else 0 end as IsTop5PctViews
  from rankings r
),
null_stress as (
  select
    q.QuestionId,
    nullif(b.DominantTag, '') as DominantTag,
    coalesce(b.TagGlobalCount, 0) as DominantTagGlobalCount,
    coalesce(a.AcceptedAnswerId, q.AcceptedAnswerId) as AcceptedAnswerIdCoalesced,
    case when q.AcceptedAnswerId is null and a.AcceptedAnswerId is not null then 1 else 0 end as AcceptedIdFilledFromJoin,
    coalesce(o.NormLocation, 'Unknown') as SafeLocation,
    coalesce(o.RepPerProfileView, 0.0) as SafeRepPerView
  from q_posts q
  left join best_tag b on b.PostId = q.QuestionId
  left join accepted_answer a on a.QuestionId = q.QuestionId
  left join owner_enriched o on o.QuestionId = q.QuestionId
),
cross_user_compare as (
  select
    q.QuestionId,
    o.OwnerReputation,
    percentile_cont(0.5) within group (order by us.Reputation) over () as GlobalMedianRep,
    avg(us.Reputation) over () as GlobalAvgRep
  from owner_enriched o
  join q_posts q on q.QuestionId = o.QuestionId
  cross join lateral (select Reputation from user_stats limit 1000000) us
),
final_scores as (
  select
    q.QuestionId,
    q.Title,
    q.Tags,
    o.OwnerReputation,
    o.AccountAgeYears,
    o.OwnerNetVotes,
    ns.DominantTag,
    ns.DominantTagGlobalCount,
    ns.SafeLocation,
    r.QScore,
    r.ViewCount,
    r.UpvoteCnt,
    r.DownvoteCnt,
    r.FavoriteCnt,
    r.BountyStarted,
    r.BountyAwarded,
    r.CommentCnt,
    r.EditCnt,
    r.DuplicateLinks,
    r.LinkedLinks,
    r.RankByScore,
    r.RankByFav,
    r.RankByNetVotes,
    r.ViewPercentile,
    e.CloseVoteEvents,
    e.ReopenEvents,
    qact.LastActivityDerived,
    qa.AcceptedAnswerId,
    ac.AcceptedScore as AcceptedAnswerScore,
    ac.AcceptedAt as AcceptedAnswerAt,
    coalesce(qa.AcceptedAnswerId, ns.AcceptedAnswerIdCoalesced) as AnyAcceptedAnswerId,
    q.IsClosed,
    q.AnswerCount,
    af.AnswererCnt,
    af.DistinctAnswerers,
    af.MaxAnswerScore,
    af.FirstAnswerAt,
    qlt.IsPopular,
    qlt.IsContentious,
    qlt.IsDuplicateLinked,
    qlt.HasBountyHistory,
    qlt.IsTop5PctViews,
    -- composite score combining many factors
    (
      coalesce(r.QScore,0)*3
      + greatest(coalesce(r.UpvoteCnt,0) - coalesce(r.DownvoteCnt,0), 0)*2
      + coalesce(r.FavoriteCnt,0)*4
      + least(coalesce(r.ViewPercentile,0), 100)*0.5
      + case when qlt.HasBountyHistory=1 then 10 else 0 end
      + case when qa.AcceptedAnswerId is not null then 8 else 0 end
      - coalesce(r.DuplicateLinks,0)*5
      - case when q.IsClosed=1 then 7 else 0 end
    )::numeric(18,2) as CompositeScore
  from q_posts q
  left join owner_enriched o on o.QuestionId = q.QuestionId
  left join rankings r on r.QuestionId = q.QuestionId
  left join edits e on e.PostId = q.QuestionId
  left join q_activity qact on qact.QuestionId = q.QuestionId
  left join accepted_answer qa on qa.QuestionId = q.QuestionId
  left join accepted_answer ac on ac.QuestionId = q.QuestionId
  left join answerers af on af.QuestionId = q.QuestionId
  left join null_stress ns on ns.QuestionId = q.QuestionId
  left join quality_flags qlt on qlt.QuestionId = q.QuestionId
),
synth as (
  select
    fs.*,
    case
      when fs.SafeLocation ilike '%united states%' or fs.SafeLocation ilike '%usa%' then 'US'
      when fs.SafeLocation ilike '%india%' then 'IN'
      when fs.SafeLocation ilike '%united kingdom%' or fs.SafeLocation ilike '%uk%' then 'UK'
      when fs.SafeLocation ilike '%germany%' then 'DE'
      when fs.SafeLocation = 'Unknown' then 'UNK'
      else 'OTHER'
    end as CountryBucket,
    row_number() over (order by fs.CompositeScore desc nulls last, fs.ViewCount desc nulls last) as GlobalRowNum,
    sum(case when fs.IsClosed=1 then 1 else 0 end) over (order by fs.CompositeScore desc nulls last rows between unbounded preceding and current row) as RunningClosedCount
  from final_scores fs
)
select
  s.QuestionId,
  coalesce(nullif(s.Title,''), '[no title]') as Title,
  s.DominantTag,
  s.DominantTagGlobalCount,
  s.OwnerReputation,
  s.AccountAgeYears,
  s.OwnerNetVotes,
  s.SafeLocation,
  s.CountryBucket,
  s.QScore,
  s.ViewCount,
  s.UpvoteCnt,
  s.DownvoteCnt,
  s.FavoriteCnt,
  s.BountyStarted,
  s.BountyAwarded,
  s.CommentCnt,
  s.EditCnt,
  s.DuplicateLinks,
  s.LinkedLinks,
  s.RankByScore,
  s.RankByFav,
  s.RankByNetVotes,
  s.ViewPercentile,
  s.CloseVoteEvents,
  s.ReopenEvents,
  s.LastActivityDerived,
  s.AcceptedAnswerId,
  s.AcceptedAnswerScore,
  s.AcceptedAnswerAt,
  s.AnyAcceptedAnswerId,
  s.IsClosed,
  s.AnswerCount,
  s.AnswererCnt,
  s.DistinctAnswerers,
  s.MaxAnswerScore,
  s.FirstAnswerAt,
  s.IsPopular,
  s.IsContentious,
  s.IsDuplicateLinked,
  s.HasBountyHistory,
  s.IsTop5PctViews,
  s.CompositeScore,
  s.GlobalRowNum,
  s.RunningClosedCount
from synth s
where
  (
    s.CompositeScore > (
      select avg(CompositeScore) from synth
    )
    or s.IsTop5PctViews = 1
  )
  and (
    s.DominantTag is null
    or s.DominantTag not ilike any (array['meta','discussion','off-topic'])
  )
order by s.CompositeScore desc nulls last, s.ViewCount desc nulls last
limit 500;