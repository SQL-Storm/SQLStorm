with
params as (
  select
    cast(365 as int) as recent_days,
    cast(0.15 as numeric) as heavy_editor_top_pct,
    cast(0.25 as numeric) as long_tail_tag_pct
),
recent_questions as (
  select
    p.Id,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    p.ClosedDate,
    date_trunc('day', p.CreationDate) as created_day
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  join params pr on true
  where p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - (pr.recent_days * interval '1 day'))
),
tag_tokens as (
  select
    rq.Id as PostId,
    unnest(string_to_array(coalesce(substring(rq.Tags, 2, length(rq.Tags)-2), ''), '><')) as TagName
  from recent_questions rq
),
tag_popularity as (
  select
    tt.TagName,
    cast(count(*) as bigint) as tag_count
  from tag_tokens tt
  group by tt.TagName
),
tag_ranked as (
  select
    tp.*,
    percent_rank() over (order by tp.tag_count desc, tp.TagName) as pct_rank_desc
  from tag_popularity tp
),
tag_bucket as (
  select
    tr.TagName,
    case
      when tr.pct_rank_desc <= (select heavy_editor_top_pct from params) then 'top'
      when tr.pct_rank_desc >= 1 - (select long_tail_tag_pct from params) then 'long_tail'
      else 'middle'
    end as bucket
  from tag_ranked tr
),
question_tag_bucket as (
  select
    tt.PostId,
    min(case when tb.bucket = 'top' then tb.bucket end) over (partition by tt.PostId) as has_top_tag,
    min(case when tb.bucket = 'long_tail' then tb.bucket end) over (partition by tt.PostId) as has_long_tail_tag
  from tag_tokens tt
  left join tag_bucket tb on tb.TagName = tt.TagName
),
edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as edit_count,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as first_edit_at,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as last_edit_at,
    count(*) filter (where ph.PostHistoryTypeId in (24)) as suggested_applied_count
  from PostHistory ph
  group by ph.PostId
),
heavy_editors as (
  select
    rq.OwnerUserId as UserId,
    count(*) as questions_authored,
    coalesce(sum(e.edit_count), 0) as total_edits_on_authored,
    avg(coalesce(e.edit_count, 0)) as avg_edits_per_question
  from recent_questions rq
  left join edits e on e.PostId = rq.Id
  where rq.OwnerUserId is not null
  group by rq.OwnerUserId
),
heavy_editor_rank as (
  select
    he.*,
    ntile(100) over (order by he.total_edits_on_authored desc nulls last, he.questions_authored desc, he.UserId) as percentile_bucket
  from heavy_editors he
),
heavy_editor_flagged as (
  select
    her.UserId,
    her.questions_authored,
    her.total_edits_on_authored,
    her.avg_edits_per_question,
    case when her.percentile_bucket <= ceil((select heavy_editor_top_pct*100 from params)) then 1 else 0 end as is_top_heavy_editor
  from heavy_editor_rank her
),
post_scores as (
  select
    p.Id,
    coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end), 0) as net_votes,
    coalesce(sum(case when v.VoteTypeId = 5 then 1 else 0 end), 0) as favorites,
    coalesce(sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount, 0) else 0 end), 0) as bounty_started,
    coalesce(sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount, 0) else 0 end), 0) as bounty_awarded
  from Posts p
  left join Votes v on v.PostId = p.Id
  group by p.Id
),
answer_stats as (
  select
    q.Id as QuestionId,
    count(a.Id) filter (where a.PostTypeId = 2) as answers_count,
    max(a.Score) filter (where a.PostTypeId = 2) as max_answer_score,
    avg(a.Score) filter (where a.PostTypeId = 2) as avg_answer_score,
    count(*) filter (where a.Id = q.AcceptedAnswerId) as has_accepted_answer
  from Posts q
  left join Posts a on a.ParentId = q.Id
  where q.PostTypeId = 1
  group by q.Id
),
comment_aggs as (
  select
    c.PostId,
    count(*) as comment_count,
    sum(c.Score) as comment_score_sum,
    avg(c.Score) as comment_score_avg,
    max(c.Score) as comment_score_max,
    min(c.Score) as comment_score_min,
    count(*) filter (where c.UserId is null) as anon_comment_count
  from Comments c
  group by c.PostId
),
link_aggs as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 1) as linked_out_count,
    count(*) filter (where pl.LinkTypeId = 3) as duplicate_of_count,
    count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as distinct_duplicate_targets
  from PostLinks pl
  group by pl.PostId
),
close_reasons as (
  select
    ph.PostId,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as closed_at,
    max(case
      when ph.PostHistoryTypeId = 10
      then cast(nullif(regexp_replace(ph.Comment, '[^0-9]', '', 'g'), '') as int)
      else null
    end) as close_reason_id
  from PostHistory ph
  group by ph.PostId
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    date_trunc('day', u.CreationDate) as UserCreatedDay,
    coalesce(nullif(trim(coalesce(u.Location,'')), ''), 'Unknown') as NormLocation,
    length(coalesce(u.AboutMe, '')) as AboutLen
  from Users u
),
question_quality as (
  select
    rq.Id as QuestionId,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    ps.net_votes,
    ps.favorites,
    ps.bounty_started,
    ps.bounty_awarded,
    asg.answers_count,
    asg.max_answer_score,
    asg.avg_answer_score,
    asg.has_accepted_answer,
    ca.comment_count,
    ca.comment_score_sum,
    ca.comment_score_avg,
    ca.comment_score_max,
    ca.comment_score_min,
    ca.anon_comment_count,
    la.linked_out_count,
    la.duplicate_of_count,
    la.distinct_duplicate_targets,
    cr.closed_at,
    cr.close_reason_id,
    qb.has_top_tag,
    qb.has_long_tail_tag,
    e.edit_count,
    e.first_edit_at,
    e.last_edit_at
  from recent_questions rq
  left join post_scores ps on ps.Id = rq.Id
  left join answer_stats asg on asg.QuestionId = rq.Id
  left join comment_aggs ca on ca.PostId = rq.Id
  left join link_aggs la on la.PostId = rq.Id
  left join close_reasons cr on cr.PostId = rq.Id
  left join question_tag_bucket qb on qb.PostId = rq.Id
  left join edits e on e.PostId = rq.Id
),
normalized as (
  select
    qq.*,
    case when qq.ViewCount > 0 then cast(qq.net_votes as numeric) / qq.ViewCount else 0 end as votes_per_view,
    case when qq.ViewCount > 0 then cast(qq.favorites as numeric) / qq.ViewCount else 0 end as favs_per_view,
    case when qq.answers_count > 0 then cast(qq.comment_count as numeric) / qq.answers_count else cast(qq.comment_count as numeric) end as comments_per_answer_or_total,
    extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qq.CreationDate)) / 3600.0 as age_hours,
    case when qq.last_edit_at is not null then extract(epoch from (coalesce(qq.last_edit_at, qq.CreationDate) - qq.CreationDate)) / 3600.0 else 0 end as time_to_last_edit_hours
  from question_quality qq
),
scored as (
  select
    n.*,
    (
      0.30 * coalesce(n.net_votes,0) +
      0.15 * coalesce(n.favorites,0) +
      0.20 * coalesce(n.answers_count,0) +
      0.10 * coalesce(n.has_accepted_answer,0) * 5 +
      0.05 * coalesce(n.comment_score_sum,0) +
      0.08 * coalesce(n.max_answer_score,0) +
      0.04 * (case when n.closed_at is null then 3 else -5 end) +
      0.04 * (case when n.has_top_tag is not null then 2 else 0 end) +
      0.04 * (case when n.has_long_tail_tag is not null then 1 else 0 end)
    ) as raw_quality,
    (case when n.closed_at is not null then 1 else 0 end) as is_closed
  from normalized n
),
ranked as (
  select
    s.*,
    row_number() over (order by s.raw_quality desc nulls last, s.net_votes desc nulls last, s.ViewCount desc nulls last, s.CreationDate desc) as quality_rank,
    dense_rank() over (order by s.is_closed, s.raw_quality desc nulls last) as closed_sensitive_rank,
    ntile(20) over (order by s.raw_quality desc nulls last) as quality_ventile
  from scored s
),
joined_users as (
  select
    r.*,
    us.Reputation,
    us.UpVotes,
    us.DownVotes,
    us.ProfileViews,
    us.UserCreatedDay,
    us.NormLocation,
    us.AboutLen,
    hef.is_top_heavy_editor,
    hef.avg_edits_per_question
  from ranked r
  left join user_stats us on us.UserId = r.OwnerUserId
  left join heavy_editor_flagged hef on hef.UserId = r.OwnerUserId
),
null_logic_checks as (
  select
    ju.*,
    coalesce(nullif(trim(coalesce(p.Title,'')), ''), '[untitled]') as SafeTitle,
    case
      when ju.close_reason_id is null then 'Open'
      when ju.close_reason_id in (101) then 'Duplicate'
      else 'ClosedOther'
    end as CloseReasonLabel
  from joined_users ju
  join Posts p on p.Id = ju.QuestionId
),
dedupe as (
  select distinct on (nlc.QuestionId)
    nlc.*
  from null_logic_checks nlc
  order by nlc.QuestionId, nlc.quality_rank
),
summary_stats as (
  select
    count(*) as total_questions,
    avg(raw_quality) as avg_quality,
    stddev_samp(raw_quality) as std_quality,
    sum(case when is_closed = 1 then 1 else 0 end) as closed_count,
    avg(case when is_closed = 1 then raw_quality else null end) as avg_quality_closed,
    avg(case when is_closed = 0 then raw_quality else null end) as avg_quality_open
  from dedupe
),
top_and_tail as (
  select
    d.*,
    case when d.quality_ventile = 1 then 'Top5%' when d.quality_ventile = 20 then 'Bottom5%' else 'Middle' end as band
  from dedupe d
)
select
  tat.QuestionId,
  tat.OwnerUserId,
  tat.SafeTitle,
  tat.CloseReasonLabel,
  tat.quality_rank,
  tat.closed_sensitive_rank,
  tat.quality_ventile,
  tat.band,
  tat.raw_quality,
  tat.net_votes,
  tat.favorites,
  tat.answers_count,
  tat.has_accepted_answer,
  tat.comment_count,
  tat.linked_out_count,
  tat.duplicate_of_count,
  tat.distinct_duplicate_targets,
  tat.Reputation,
  tat.UpVotes,
  tat.DownVotes,
  tat.ProfileViews,
  tat.NormLocation,
  tat.is_top_heavy_editor,
  tat.avg_edits_per_question,
  ss.total_questions,
  ss.avg_quality,
  ss.std_quality,
  ss.closed_count,
  ss.avg_quality_closed,
  ss.avg_quality_open
from top_and_tail tat
cross join summary_stats ss
where
  (
    (tat.is_closed = 0 and tat.quality_ventile <= 10 and (tat.has_top_tag is not null or tat.has_long_tail_tag is null))
    or
    (tat.is_closed = 1 and tat.quality_ventile >= 15 and tat.duplicate_of_count >= coalesce(tat.distinct_duplicate_targets,0))
  )
  and (
    tat.net_votes >= 0
    or (tat.net_votes < 0 and tat.favorites > abs(tat.net_votes))
  )
  and (
    tat.Reputation is null
    or (tat.Reputation >= 100 and (tat.UpVotes - coalesce(tat.DownVotes,0)) >= 0)
  )
order by
  tat.band,
  tat.quality_rank
limit 250;