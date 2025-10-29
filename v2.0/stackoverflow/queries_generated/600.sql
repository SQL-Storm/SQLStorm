-- {"query": "600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2909} 
with recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    coalesce(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><'), array[]::varchar[]) as tag_array
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
user_activity as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.CreationDate as UserCreated,
    u.LastAccessDate,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormLocation,
    case
      when u.WebsiteUrl ilike '%github%' then 'GitHub'
      when u.WebsiteUrl ilike '%stack%' then 'Stack'
      when u.WebsiteUrl is null or u.WebsiteUrl = '' then 'None'
      else 'Other'
    end as SiteType
  from Users u
),
answers_stats as (
  select
    q.Id as QuestionId,
    count(a.Id) as AnswerCount,
    avg(a.Score)::numeric(18,2) as AvgAnswerScore,
    max(a.CreationDate) as LastAnswerDate
  from Posts q
  left join Posts a
    on a.ParentId = q.Id
    and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id
),
comment_aggs as (
  select
    c.PostId,
    count(*) filter (where c.Score > 0) as PosComments,
    count(*) filter (where c.Score <= 0 or c.Score is null) as NonPosComments,
    max(c.CreationDate) as LastCommentDate,
    coalesce(sum(c.Score),0) as SumCommentScore
  from Comments c
  group by c.PostId
),
vote_aggs as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as Upvotes,
    count(*) filter (where v.VoteTypeId = 3) as Downvotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    count(*) filter (where v.VoteTypeId = 8) as BountyStarts,
    count(*) filter (where v.VoteTypeId = 9) as BountyCloses,
    coalesce(sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end),0) as BountyAmountTotal
  from Votes v
  group by v.PostId
),
dup_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
    min(pl.CreationDate) filter (where pl.LinkTypeId = 3) as FirstDupLinkDate
  from PostLinks pl
  group by pl.PostId
),
close_events as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    count(*) filter (where ph.PostHistoryTypeId in (12,13)) as DeleteUndeleteEvents,
    max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment,'') end) as CloseReasonIdStr
  from PostHistory ph
  group by ph.PostId
),
tag_exploded as (
  select
    rq.QuestionId,
    lower(trim(t)) as tag
  from recent_questions rq
  cross join lateral unnest(rq.tag_array) as t
),
tag_metrics as (
  select
    te.QuestionId,
    count(*) as TagCount,
    string_agg(te.tag, ',' order by te.tag) as TagList,
    sum(case when tg.IsModeratorOnly then 1 else 0 end) as ModOnlyTagCount,
    sum(case when tg.IsRequired then 1 else 0 end) as RequiredTagCount,
    sum(coalesce(tg.Count,0)) as TagPopularitySum
  from tag_exploded te
  left join Tags tg
    on tg.TagName = te.tag
  group by te.QuestionId
),
owner_badges as (
  select
    b.UserId,
    count(*) as TotalBadges,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
ranked_questions as (
  select
    rq.QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.Title,
    coalesce(v.Upvotes,0) as Upvotes,
    coalesce(v.Downvotes,0) as Downvotes,
    coalesce(v.Favorites,0) as Favorites,
    coalesce(v.BountyAmountTotal,0) as BountyAmountTotal,
    coalesce(a.AnswerCount,0) as AnswerCount,
    coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(c.PosComments,0) as PosComments,
    coalesce(c.NonPosComments,0) as NonPosComments,
    coalesce(c.SumCommentScore,0) as SumCommentScore,
    coalesce(d.DuplicateLinks,0) as DuplicateLinks,
    coalesce(d.LinkedLinks,0) as LinkedLinks,
    tm.TagCount,
    tm.TagList,
    tm.ModOnlyTagCount,
    tm.RequiredTagCount,
    tm.TagPopularitySum,
    greatest(coalesce(a.LastAnswerDate, timestamp 'epoch'), coalesce(c.LastCommentDate, timestamp 'epoch')) as LastInteractionDate,
    coalesce(cl.CloseEvents,0) as CloseEvents,
    cl.FirstCloseDate,
    cl.LastReopenDate,
    cl.ReopenEvents,
    cl.DeleteUndeleteEvents,
    nullif(cl.CloseReasonIdStr,'') as CloseReasonIdStr
  from recent_questions rq
  left join vote_aggs v on v.PostId = rq.QuestionId
  left join answers_stats a on a.QuestionId = rq.QuestionId
  left join comment_aggs c on c.PostId = rq.QuestionId
  left join dup_links d on d.PostId = rq.QuestionId
  left join tag_metrics tm on tm.QuestionId = rq.QuestionId
  left join close_events cl on cl.PostId = rq.QuestionId
),
owner_enriched as (
  select
    rq.*,
    ua.Reputation,
    ua.UpVotes as UserUpVotes,
    ua.DownVotes as UserDownVotes,
    ua.Views as UserViews,
    ua.UserCreated,
    ua.LastAccessDate,
    ua.NormLocation,
    ua.SiteType,
    ob.TotalBadges,
    ob.GoldBadges,
    ob.SilverBadges,
    ob.BronzeBadges,
    ob.LastBadgeDate
  from ranked_questions rq
  left join user_activity ua on ua.UserId = rq.OwnerUserId
  left join owner_badges ob on ob.UserId = rq.OwnerUserId
),
scored as (
  select
    oe.*,
    case
      when oe.CloseEvents > 0 then 0
      else 1
    end as IsOpen,
    case
      when oe.TagCount = 0 then 0
      else 1
    end as HasTags,
    (
      coalesce(oe.Score,0)*2
      + coalesce(oe.Upvotes,0)*1.5
      - coalesce(oe.Downvotes,0)*2
      + least(coalesce(oe.ViewCount,0)/100, 500)
      + coalesce(oe.AnswerCount,0)*3
      + coalesce(oe.AvgAnswerScore,0)*1.2
      + coalesce(oe.Favorites,0)*1.5
      + coalesce(oe.SumCommentScore,0)*0.5
      + (case when oe.DuplicateLinks > 0 then -50 else 0 end)
      + (case when oe.ModOnlyTagCount > 0 then -5*oe.ModOnlyTagCount else 0 end)
      + (case when oe.RequiredTagCount > 0 then 3*oe.RequiredTagCount else 0 end)
      + least(coalesce(oe.TagPopularitySum,0)/1000.0, 250)
      + (case when oe.IsOpen = 1 then 25 else -25 end)
      + (case when oe.BountyAmountTotal > 0 then 10 + least(oe.BountyAmountTotal/50.0, 100) else 0 end)
      + (case when coalesce(oe.Reputation,0) > 10000 then 20
              when coalesce(oe.Reputation,0) > 1000 then 10
              else 0 end)
    )::numeric(18,2) as PerfScore
  from owner_enriched oe
),
ranked as (
  select
    s.*,
    row_number() over (
      partition by case when s.TagCount = 0 then 'untagged' else 'tagged' end
      order by s.PerfScore desc, s.LastInteractionDate desc nulls last, s.CreationDate desc
    ) as rn_tag_partition,
    ntile(10) over (order by s.PerfScore desc) as decile_global,
    rank() over (order by s.PerfScore desc) as rk_global,
    dense_rank() over (order by s.TagPopularitySum desc nulls last) as dr_tag_popularity
  from scored s
),
closed_reason_lookup as (
  select
    r.QuestionId,
    cr.Name as CloseReasonName
  from (
    select
      rq.QuestionId,
      nullif(trim(rq.CloseReasonIdStr), '')::int as CloseReasonId
    from ranked rq
    where rq.CloseReasonIdStr ~ '^[0-9]+$'
  ) r
  left join CloseReasonTypes cr
    on cr.Id = r.CloseReasonId
)
select
  r.QuestionId,
  coalesce(r.Title, '(no title)') as Title,
  r.CreationDate,
  r.LastInteractionDate,
  r.Score,
  r.ViewCount,
  r.Upvotes,
  r.Downvotes,
  r.Favorites,
  r.AnswerCount,
  r.AvgAnswerScore,
  r.PosComments,
  r.NonPosComments,
  r.DuplicateLinks,
  r.LinkedLinks,
  r.CloseEvents,
  r.ReopenEvents,
  r.TagCount,
  r.TagList,
  r.ModOnlyTagCount,
  r.RequiredTagCount,
  r.TagPopularitySum,
  r.OwnerUserId,
  r.Reputation,
  r.UserUpVotes,
  r.UserDownVotes,
  r.UserViews,
  r.NormLocation,
  r.SiteType,
  r.TotalBadges,
  r.GoldBadges,
  r.SilverBadges,
  r.BronzeBadges,
  r.PerfScore,
  r.decile_global,
  r.rk_global,
  r.dr_tag_popularity,
  r.rn_tag_partition,
  coalesce(crl.CloseReasonName, case when r.CloseEvents > 0 then 'Closed (unknown reason)' else null end) as CloseReasonName,
  case
    when r.TagCount = 0 then 'untagged'
    when r.TagCount = 1 then 'single-tag'
    when r.TagCount between 2 and 4 then 'multi-tag'
    else 'many-tags'
  end as TagBucket,
  case
    when r.AnswerCount = 0 then 'unanswered'
    when r.AnswerCount between 1 and 2 then 'few answers'
    when r.AnswerCount between 3 and 5 then 'several answers'
    else 'many answers'
  end as AnswerBucket
from ranked r
left join closed_reason_lookup crl
  on crl.QuestionId = r.QuestionId
where
  -- complex predicate mixing null logic and expressions
  (
    (r.PerfScore > 50 and coalesce(r.TagPopularitySum,0) > 0)
    or
    (r.PerfScore > 150 and r.TagCount is distinct from 0)
    or
    (r.CloseEvents = 0 and r.AnswerCount >= 1 and r.Upvotes - r.Downvotes >= 5)
  )
  and coalesce(r.ViewCount,0) >= 0
  and (
    r.LastInteractionDate is null
    or r.LastInteractionDate >= r.CreationDate
  )
  and (
    r.NormLocation is null
    or r.NormLocation not ilike '%test%'
  )
order by r.PerfScore desc, r.LastInteractionDate desc nulls last
limit 500;