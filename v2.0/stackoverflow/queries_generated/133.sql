-- {"query": "133.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3494} 
with params as (
  select 
    365::int as days_back,
    50::int as top_n,
    0.25::numeric as heavy_editor_threshold_ratio
),
recent_posts as (
  select p.*
  from Posts p
  cross join params pr
  where p.CreationDate >= now() - (pr.days_back || ' days')::interval
    and p.PostTypeId in (1,2)
),
post_core as (
  select
    rp.Id,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    coalesce(rp.OwnerUserId, -1) as OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount
  from recent_posts rp
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm
  from Users u
),
post_votes as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
    sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
    min(v.CreationDate) as FirstVoteAt,
    max(v.CreationDate) as LastVoteAt,
    count(*) as TotalVotes
  from Votes v
  group by v.PostId
),
comment_dynamics as (
  select
    c.PostId,
    count(*) as CommentCountAll,
    sum(case when c.Score > 0 then 1 else 0 end) as PosComments,
    sum(case when c.Score < 0 then 1 else 0 end) as NegComments,
    max(c.Score) as MaxCommentScore,
    min(c.CreationDate) as FirstCommentAt,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
history_edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
    count(distinct ph.UserId) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24) and ph.UserId is not null) as DistinctEditors,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditAt,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36)) as LastModEventAt
  from PostHistory ph
  group by ph.PostId
),
postlinks_agg as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedOutCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateOfCount,
    count(*) as TotalLinks,
    min(pl.CreationDate) as FirstLinkAt,
    max(pl.CreationDate) as LastLinkAt
  from PostLinks pl
  group by pl.PostId
),
tag_explode as (
  select
    pc.Id as PostId,
    unnest(string_to_array(substring(pc.Tags from 2 for length(pc.Tags)-2), '><')) as tag
  from post_core pc
  where pc.PostTypeId = 1
    and pc.Tags is not null
    and pc.Tags like '<%>'
),
tag_rank as (
  select
    te.tag,
    count(*) as tag_post_count
  from tag_explode te
  group by te.tag
),
tag_class as (
  select
    te.PostId,
    array_agg(te.tag order by tr.tag_post_count desc, te.tag) as tags_by_popularity,
    max(case when lower(te.tag) in ('sql','postgresql','mysql','sqlite','tsql','plsql') then 1 else 0 end) as is_db_related
  from tag_explode te
  join tag_rank tr on tr.tag = te.tag
  group by te.PostId
),
answers_by_question as (
  select
    a.ParentId as QuestionId,
    count(*) as Answers,
    sum(case when a.Score > 0 then 1 else 0 end) as PosAnswers,
    max(a.Score) as MaxAnswerScore,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
  group by a.ParentId
),
heavily_edited_posts as (
  select
    he.PostId,
    he.EditEvents,
    he.DistinctEditors,
    (he.DistinctEditors::numeric / nullif(he.EditEvents,0)) as editor_concentration,
    case 
      when he.EditEvents >= 5 and he.DistinctEditors >= 3 then 1
      when he.EditEvents >= 3 and he.DistinctEditors >= 2 then 1
      else 0
    end as is_heavily_edited_flag
  from history_edits he
),
user_badges as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as Gold,
    sum(case when b.Class = 2 then 1 else 0 end) as Silver,
    sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
    count(*) as TotalBadges,
    max(b.Date) as LastBadgeAt
  from Badges b
  group by b.UserId
),
post_quality_signal as (
  select
    pc.Id as PostId,
    pc.PostTypeId,
    pc.Score,
    coalesce(pv.UpVotes,0) as UpVotes,
    coalesce(pv.DownVotes,0) as DownVotes,
    coalesce(pv.Favorites,0) as Favorites,
    coalesce(pv.BountyAwarded,0) as BountyAwarded,
    case when pc.PostTypeId = 1 then coalesce(abq.HasAccepted,0) else 0 end as HasAccepted,
    case when pc.PostTypeId = 1 then coalesce(abq.MaxAnswerScore,0) else 0 end as MaxAnswerScore,
    coalesce(cd.CommentCountAll,0) as Comments,
    coalesce(he.EditEvents,0) as EditEvents,
    coalesce(he.CloseEvents,0) as CloseEvents,
    coalesce(pl.TotalLinks,0) as Links,
    -- composite score emphasizing community validation
    (
      1.0*coalesce(pv.UpVotes,0)
      - 1.5*coalesce(pv.DownVotes,0)
      + 0.5*coalesce(pv.Favorites,0)
      + 0.25*coalesce(cd.PosComments,0)
      - 0.25*coalesce(cd.NegComments,0)
      + 0.75*case when pc.PostTypeId = 1 then coalesce(abq.HasAccepted,0) else 0 end
      + 0.05*coalesce(abq.MaxAnswerScore,0)
      + 0.1*coalesce(pv.BountyAwarded,0)
      + 0.05*coalesce(pl.LinkedOutCount,0)
      - 0.10*coalesce(he.CloseEvents,0)
    ) as quality_score_raw
  from post_core pc
  left join post_votes pv on pv.PostId = pc.Id
  left join comment_dynamics cd on cd.PostId = pc.Id
  left join history_edits he on he.PostId = pc.Id
  left join postlinks_agg pl on pl.PostId = pc.Id
  left join answers_by_question abq on abq.QuestionId = pc.Id
),
normalized_quality as (
  select
    pqs.*,
    percentile_cont(0.5) within group (order by quality_score_raw) over () as p50,
    percentile_cont(0.9) within group (order by quality_score_raw) over () as p90
  from post_quality_signal pqs
),
final_scored as (
  select
    nq.PostId,
    nq.PostTypeId,
    nq.Score,
    nq.UpVotes,
    nq.DownVotes,
    nq.Favorites,
    nq.BountyAwarded,
    nq.HasAccepted,
    nq.MaxAnswerScore,
    nq.Comments,
    nq.EditEvents,
    nq.CloseEvents,
    nq.Links,
    nq.quality_score_raw,
    case 
      when nq.quality_score_raw >= nq.p90 then 'elite'
      when nq.quality_score_raw >= nq.p50 then 'strong'
      else 'normal'
    end as quality_band
  from normalized_quality nq
),
owner_enriched as (
  select
    fc.*,
    us.UserId,
    us.Reputation,
    us.LocationNorm,
    ub.TotalBadges,
    ub.Gold,
    ub.Silver,
    ub.Bronze
  from final_scored fc
  left join post_core pc on pc.Id = fc.PostId
  left join user_stats us on us.UserId = pc.OwnerUserId
  left join user_badges ub on ub.UserId = pc.OwnerUserId
),
time_windows as (
  select
    pc.Id as PostId,
    pc.CreationDate,
    generate_series(
      date_trunc('day', pc.CreationDate),
      date_trunc('day', now()),
      interval '7 days'
    ) as wk
  from post_core pc
),
activity_rollup as (
  select
    tw.PostId,
    tw.wk,
    coalesce(sum(pv.TotalVotes) filter (where pv.FirstVoteAt >= tw.wk and pv.FirstVoteAt < tw.wk + interval '7 days'),0) as votes_started,
    coalesce(sum(cd.CommentCountAll) filter (where cd.FirstCommentAt >= tw.wk and cd.FirstCommentAt < tw.wk + interval '7 days'),0) as comments_started,
    coalesce(sum(he.EditEvents) filter (where he.LastEditAt >= tw.wk and he.LastEditAt < tw.wk + interval '7 days'),0) as edits_happened
  from time_windows tw
  left join post_votes pv on pv.PostId = tw.PostId
  left join comment_dynamics cd on cd.PostId = tw.PostId
  left join history_edits he on he.PostId = tw.PostId
  group by tw.PostId, tw.wk
),
recent_bursty as (
  select
    ar.PostId,
    sum(ar.votes_started + ar.comments_started + ar.edits_happened) filter (where ar.wk >= now() - interval '28 days') as last_4w_activity,
    sum(ar.votes_started + ar.comments_started + ar.edits_happened) filter (where ar.wk >= now() - interval '84 days' and ar.wk < now() - interval '28 days') as prev_8w_activity
  from activity_rollup ar
  group by ar.PostId
),
post_labels as (
  select
    oe.PostId,
    case 
      when rb.last_4w_activity is null then 'cold'
      when coalesce(rb.last_4w_activity,0) >= coalesce(rb.prev_8w_activity,0) * 2 and coalesce(rb.last_4w_activity,0) >= 5 then 'surging'
      when coalesce(rb.last_4w_activity,0) = 0 and coalesce(rb.prev_8w_activity,0) >= 5 then 'cooling'
      else 'steady'
    end as momentum,
    case 
      when oe.Reputation >= 50000 then 'legend'
      when oe.Reputation >= 10000 then 'high-rep'
      when oe.Reputation >= 2000 then 'mid-rep'
      when oe.Reputation is null then 'anon-or-deleted'
      else 'low-rep'
    end as author_tier
  from owner_enriched oe
  left join recent_bursty rb on rb.PostId = oe.PostId
),
question_enrichment as (
  select
    pc.Id as PostId,
    tc.tags_by_popularity,
    tc.is_db_related
  from post_core pc
  left join tag_class tc on tc.PostId = pc.Id
),
heavy_edit_flag as (
  select
    pc.Id as PostId,
    case 
      when hep.is_heavily_edited_flag = 1 then 1
      when hep.editor_concentration is not null and hep.editor_concentration < (select heavy_editor_threshold_ratio from params) then 1
      else 0
    end as is_heavily_edited
  from post_core pc
  left join heavily_edited_posts hep on hep.PostId = pc.Id
),
ranked_posts as (
  select
    oe.*,
    pl.momentum,
    pl.author_tier,
    qe.tags_by_popularity,
    qe.is_db_related,
    hef.is_heavily_edited,
    row_number() over (
      partition by oe.PostTypeId
      order by 
        oe.quality_score_raw desc,
        coalesce(oe.Reputation, -1) desc,
        oe.UpVotes desc,
        oe.Favorites desc,
        oe.DownVotes asc,
        oe.PostId asc
    ) as rn
  from owner_enriched oe
  left join post_labels pl on pl.PostId = oe.PostId
  left join question_enrichment qe on qe.PostId = oe.PostId
  left join heavy_edit_flag hef on hef.PostId = oe.PostId
)
select
  rp.PostId,
  case rp.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostType,
  rp.quality_band,
  rp.quality_score_raw as QualityScore,
  rp.UpVotes,
  rp.DownVotes,
  rp.Favorites,
  rp.BountyAwarded,
  rp.HasAccepted,
  rp.MaxAnswerScore,
  rp.Comments,
  rp.EditEvents,
  rp.CloseEvents,
  rp.Links,
  coalesce(rp.Reputation, -1) as OwnerReputation,
  coalesce(rp.TotalBadges, 0) as OwnerBadges,
  rp.author_tier,
  rp.momentum,
  rp.is_heavily_edited,
  case 
    when rp.PostTypeId = 1 then array_to_string(coalesce(rp.tags_by_popularity, array[]::varchar[]), ',')
    else null
  end as TagsByPopularity,
  case 
    when rp.PostTypeId = 1 then rp.is_db_related
    else null
  end as IsDbRelated,
  -- synthetic shard key to exercise expression + null logic
  coalesce(
    md5(
      coalesce(rp.PostId::text,'') || ':' ||
      coalesce(rp.Reputation::text,'') || ':' ||
      coalesce(rp.UpVotes::text,'') || ':' ||
      coalesce(rp.DownVotes::text,'')
    ),
    md5(rp.PostId::text)
  ) as ShardKey
from ranked_posts rp
cross join params pr
where rp.rn <= pr.top_n
order by rp.PostTypeId, rp.rn;