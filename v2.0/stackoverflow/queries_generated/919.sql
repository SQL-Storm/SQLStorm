-- {"query": "919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2715} 
with params as (
  select
    cast(365 as int) as lookback_days,
    cast(0.25 as numeric) as heavy_editor_ratio
),
recent_activity as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    (p.ViewCount::numeric / nullif(greatest(extract(epoch from (now() - p.CreationDate)) / 86400.0, 1), 0)) as views_per_day,
    case when p.Tags is null then 0 else cardinality(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) end as tag_count
  from Posts p
  where p.PostTypeId in (1,2)
    and p.CreationDate >= now() - interval '730 days'
),
edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as edit_count,
    min(ph.CreationDate) as first_edit_at,
    max(ph.CreationDate) as last_edit_at,
    count(distinct ph.UserId) as distinct_editors,
    count(*) filter (where ph.UserId is null) as anon_edits
  from PostHistory ph
  where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)
  group by ph.PostId
),
votes as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as upvotes,
    count(*) filter (where v.VoteTypeId = 3) as downvotes,
    count(*) filter (where v.VoteTypeId in (8,9)) as bounty_events,
    sum(coalesce(v.BountyAmount,0)) filter (where v.VoteTypeId in (8,9)) as bounty_amount
  from Votes v
  where v.CreationDate >= now() - (select lookback_days || ' days'::interval from params)
  group by v.PostId
),
comments as (
  select
    c.PostId,
    count(*) as comment_cnt,
    max(c.Score) as max_comment_score,
    avg(c.Score) as avg_comment_score
  from Comments c
  where c.CreationDate >= now() - interval '180 days'
  group by c.PostId
),
post_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 1) as linked_cnt,
    count(*) filter (where pl.LinkTypeId = 3) as duplicate_cnt
  from PostLinks pl
  group by pl.PostId
),
owners as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreated,
    u.DisplayName,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    coalesce(nullif(trim(coalesce(u.Location,'')),''), 'Unknown') as CleanLocation
  from Users u
),
heavy_editors as (
  select
    ph.PostId,
    count(*) filter (where ph.UserId = p.OwnerUserId) as owner_edits,
    count(*) filter (where ph.UserId <> p.OwnerUserId and ph.UserId is not null) as non_owner_edits
  from PostHistory ph
  join Posts p on p.Id = ph.PostId
  where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)
  group by ph.PostId
),
tag_expansion as (
  select
    r.PostId,
    unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) as TagName
  from recent_activity r
  where r.PostTypeId = 1
    and r.Tags is not null
),
tag_stats as (
  select
    te.PostId,
    count(*) filter (where t.IsModeratorOnly) as mod_only_tags,
    count(*) filter (where t.IsRequired) as required_tags,
    sum(coalesce(t.Count,0)) as sum_tag_popularity,
    max(t.Count) as max_tag_popularity
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.TagName)
  group by te.PostId
),
accepted_answer_age as (
  select
    q.Id as QuestionId,
    a.Id as AnswerId,
    a.CreationDate,
    extract(epoch from (a.CreationDate - q.CreationDate))/3600.0 as hours_to_accept
  from Posts q
  join Posts a on a.Id = q.AcceptedAnswerId
),
owner_badges as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as gold_badges,
    count(*) filter (where b.Class = 2) as silver_badges,
    count(*) filter (where b.Class = 3) as bronze_badges,
    count(*) filter (where b.TagBased = 1) as tag_badges,
    max(b.Date) as last_badge_at
  from Badges b
  group by b.UserId
),
ranked_posts as (
  select
    r.PostId,
    r.PostTypeId,
    r.OwnerUserId,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.CommentCount,
    r.CreationDate,
    r.LastActivityDate,
    r.Title,
    r.views_per_day,
    r.tag_count,
    coalesce(e.edit_count, 0) as edit_count,
    coalesce(e.distinct_editors, 0) as distinct_editors,
    coalesce(e.anon_edits, 0) as anon_edits,
    coalesce(v.upvotes, 0) as upvotes,
    coalesce(v.downvotes, 0) as downvotes,
    coalesce(v.bounty_events, 0) as bounty_events,
    coalesce(v.bounty_amount, 0) as bounty_amount,
    coalesce(c.comment_cnt, 0) as comment_cnt,
    coalesce(c.max_comment_score, 0) as max_comment_score,
    coalesce(c.avg_comment_score, 0) as avg_comment_score,
    coalesce(l.linked_cnt, 0) as linked_cnt,
    coalesce(l.duplicate_cnt, 0) as duplicate_cnt,
    coalesce(ts.mod_only_tags, 0) as mod_only_tags,
    coalesce(ts.required_tags, 0) as required_tags,
    coalesce(ts.sum_tag_popularity, 0) as sum_tag_popularity,
    coalesce(ts.max_tag_popularity, 0) as max_tag_popularity,
    case when aa.hours_to_accept is null then nullif(-1,-1) else aa.hours_to_accept end as hours_to_accept,
    case
      when r.PostTypeId = 1 then greatest(1, r.ViewCount) * (coalesce(v.upvotes,0) - coalesce(v.downvotes,0) + r.Score)
      when r.PostTypeId = 2 then greatest(1, r.Score + coalesce(v.upvotes,0) - coalesce(v.downvotes,0))
      else 1
    end as raw_signal
  from recent_activity r
  left join edits e on e.PostId = r.PostId
  left join votes v on v.PostId = r.PostId
  left join comments c on c.PostId = r.PostId
  left join post_links l on l.PostId = r.PostId
  left join tag_stats ts on ts.PostId = r.PostId
  left join accepted_answer_age aa on aa.QuestionId = r.PostId
),
normalized as (
  select
    rp.*,
    dense_rank() over (order by rp.raw_signal desc nulls last) as signal_rank,
    sum(rp.raw_signal) over () as total_signal,
    avg(rp.raw_signal) over () as avg_signal,
    stddev_pop(rp.raw_signal) over () as std_signal,
    row_number() over (partition by rp.PostTypeId order by rp.raw_signal desc nulls last) as type_rownum
  from ranked_posts rp
),
owner_enriched as (
  select
    n.*,
    o.DisplayName as OwnerName,
    o.Reputation as OwnerRep,
    o.CleanLocation as OwnerLocation,
    ob.gold_badges,
    ob.silver_badges,
    ob.bronze_badges,
    ob.tag_badges,
    ob.last_badge_at,
    he.owner_edits,
    he.non_owner_edits,
    case
      when coalesce(he.non_owner_edits,0) = 0 then 1.0
      else coalesce(he.owner_edits::numeric,0) / nullif(he.non_owner_edits::numeric,0)
    end as owner_to_others_edit_ratio
  from normalized n
  left join owners o on o.UserId = n.OwnerUserId
  left join owner_badges ob on ob.UserId = n.OwnerUserId
  left join heavy_editors he on he.PostId = n.PostId
),
outliers as (
  select
    oe.*,
    case when oe.raw_signal is not null and nvl(oe.std_signal,0) <> 0
         then (oe.raw_signal - oe.avg_signal) / nullif(oe.std_signal,0)
         else null end as zscore,
    case
      when oe.duplicate_cnt > 0 then 'Duplicate'
      when oe.mod_only_tags > 0 then 'Mod-Only'
      when oe.required_tags > 0 then 'Required'
      when oe.tag_count = 0 then 'Untagged'
      else 'Normal'
    end as post_flag
  from owner_enriched oe
),
filtered as (
  select
    o.*
  from outliers o
  where (
    o.PostTypeId = 1 and (o.AnswerCount >= 1 or o.duplicate_cnt > 0)
    or o.PostTypeId = 2 and o.Score >= 0
  )
  and coalesce(o.downvotes,0) <= coalesce(o.upvotes,0) * 2
  and (o.owner_to_others_edit_ratio is null or o.owner_to_others_edit_ratio >= (select heavy_editor_ratio from params))
),
rollup as (
  select
    f.*,
    sum(case when f.PostTypeId = 1 then 1 else 0 end) over () as total_questions,
    sum(case when f.PostTypeId = 2 then 1 else 0 end) over () as total_answers,
    sum(f.comment_cnt) over () as total_comments,
    sum(f.upvotes) over () as total_upvotes,
    sum(f.downvotes) over () as total_downvotes
  from filtered f
),
rank_buckets as (
  select
    r.*,
    ntile(10) over (order by coalesce(r.raw_signal,0) desc) as decile,
    ntile(4) over (partition by r.PostTypeId order by coalesce(r.raw_signal,0) desc) as quartile_by_type
  from rollup r
)
select
  rb.PostId,
  rb.PostTypeId,
  coalesce(rb.Title, concat('Answer #', rb.PostId)) as TitleOrAnswer,
  rb.OwnerUserId,
  coalesce(rb.OwnerName, '(unknown)') as OwnerName,
  rb.OwnerRep,
  rb.OwnerLocation,
  rb.Score,
  rb.ViewCount,
  rb.views_per_day,
  rb.AnswerCount,
  rb.CommentCount,
  rb.upvotes,
  rb.downvotes,
  rb.bounty_events,
  rb.bounty_amount,
  rb.edit_count,
  rb.distinct_editors,
  rb.owner_edits,
  rb.non_owner_edits,
  rb.owner_to_others_edit_ratio,
  rb.tag_count,
  rb.mod_only_tags,
  rb.required_tags,
  rb.sum_tag_popularity,
  rb.max_tag_popularity,
  rb.linked_cnt,
  rb.duplicate_cnt,
  rb.hours_to_accept,
  rb.zscore,
  rb.post_flag,
  rb.signal_rank,
  rb.decile,
  rb.quartile_by_type,
  rb.total_questions,
  rb.total_answers,
  rb.total_comments,
  rb.total_upvotes,
  rb.total_downvotes
from rank_buckets rb
where rb.decile in (1, 2, 3, 10)
order by rb.decile asc, rb.signal_rank asc, rb.PostId asc
limit 500;