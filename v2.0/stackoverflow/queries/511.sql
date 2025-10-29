-- {"query": "511.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3274}
with
params as (
  select
    timestamp '2015-01-01' as start_date,
    timestamp '2021-12-31' as end_date,
    10 as min_answers,
    5 as min_comments
),
q as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score as QScore,
    p.ViewCount,
    p.OwnerUserId as QOwnerId,
    p.AcceptedAnswerId,
    coalesce(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), array[]::varchar[]) as tag_arr,
    cardinality(coalesce(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), array[]::varchar[])) as tag_cnt,
    p.Title,
    p.AnswerCount,
    p.CommentCount
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  cross join params prm
  where p.CreationDate between prm.start_date and prm.end_date
),
a as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AOwnerId,
    a.Score as AScore,
    a.CreationDate as ACreated,
    a.LastActivityDate as ALastActivity
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
),
c as (
  select
    c.PostId,
    count(*) as comments,
    sum(case when c.Score >= 5 then 1 else 0 end) as high_score_comments,
    avg(nullif(length(c.Text),0)) as avg_comment_len
  from Comments c
  group by c.PostId
),
v as (
  select
    v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 else 0 end) as upvotes,
    sum(case when vt.Name = 'DownMod' then 1 else 0 end) as downvotes,
    sum(case when vt.Name = 'Favorite' then 1 else 0 end) as favorites
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
u as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    case
      when u.Reputation >= 100000 then 'Legend'
      when u.Reputation >= 25000 then 'Expert'
      when u.Reputation >= 5000 then 'Pro'
      when u.Reputation >= 1000 then 'Intermediate'
      else 'Newbie'
    end as rep_band,
    cast(date_part('year', u.CreationDate) as integer) as join_year,
    coalesce(nullif(trim(u.Location),''),'Unknown') as LocationNorm
  from Users u
),
ub as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as gold,
    sum(case when b.Class = 2 then 1 else 0 end) as silver,
    sum(case when b.Class = 3 then 1 else 0 end) as bronze,
    count(*) as total_badges,
    sum(case when b.TagBased = true then 1 else 0 end) as tag_badges
  from Badges b
  group by b.UserId
),
pl as (
  select
    pl.PostId,
    sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as dup_out,
    sum(case when lt.Name = 'Linked' then 1 else 0 end) as link_out
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
closed as (
  select
    ph.PostId,
    min(ph.CreationDate) as first_closed_at,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as reopened_at,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as last_closed_at,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as last_close_reason_id_text
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
accepted as (
  select
    q.QuestionId,
    q.AcceptedAnswerId,
    a.AOwnerId as AcceptedOwnerId,
    a.AScore as AcceptedScore,
    a.ACreated as AcceptedCreated
  from q
  left join a on a.AnswerId = q.AcceptedAnswerId
),
a_agg as (
  select
    a.QuestionId,
    count(*) as answers_total,
    count(*) filter (where a.AScore > 0) as answers_positive,
    max(a.AScore) as max_answer_score,
    avg(a.AScore) as avg_answer_score,
    min(a.ACreated) as first_answer_at,
    max(a.ALastActivity) as last_answer_activity
  from a
  group by a.QuestionId
),
eng as (
  select
    p.Id as PostId,
    coalesce(v.upvotes,0) as upvotes,
    coalesce(v.downvotes,0) as downvotes,
    coalesce(v.favorites,0) as favorites,
    coalesce(c.comments,0) as comments,
    coalesce(c.high_score_comments,0) as high_score_comments,
    coalesce(c.avg_comment_len,0) as avg_comment_len,
    cast((coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) as integer) as vote_delta,
    cast((coalesce(v.upvotes,0) + coalesce(v.downvotes,0) + coalesce(c.comments,0)) as integer) as activity_sum
  from Posts p
  left join v on v.PostId = p.Id
  left join c on c.PostId = p.Id
),
q_tagged as (
  select
    q.QuestionId,
    lower(trim(t)) as tag
  from q
  cross join lateral unnest(q.tag_arr) as t
),
top_tags as (
  select tag, count(*) as tag_q_count
  from q_tagged
  group by tag
  having count(*) >= 100
),
q_metrics as (
  select
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.QScore,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.tag_cnt,
    coalesce(pl.dup_out,0) as dup_out,
    coalesce(pl.link_out,0) as link_out,
    e.vote_delta,
    e.activity_sum,
    coalesce(aagg.answers_total,0) as answers_total,
    coalesce(aagg.max_answer_score, null) as max_answer_score,
    coalesce(aagg.avg_answer_score, null) as avg_answer_score,
    case when cl.first_closed_at is not null then 1 else 0 end as is_closed,
    cast(
      (
        greatest(q.QScore,0)*2
        + least(coalesce(e.vote_delta,0), 500)
        + coalesce(e.favorites,0)
        + coalesce(e.comments,0)
        + coalesce(q.ViewCount,0)/100.0
        + coalesce(aagg.answers_total,0)*3
        - coalesce(pl.dup_out,0)*5
      ) as numeric
    ) as composite_score
  from q
  left join eng e on e.PostId = q.QuestionId
  left join pl on pl.PostId = q.QuestionId
  left join a_agg aagg on aagg.QuestionId = q.QuestionId
  left join closed cl on cl.PostId = q.QuestionId
),
q_win as (
  select
    qm.QuestionId,
    qm.Title,
    qm.CreationDate,
    qm.QScore,
    qm.ViewCount,
    qm.AnswerCount,
    qm.CommentCount,
    qm.tag_cnt,
    qm.dup_out,
    qm.link_out,
    qm.vote_delta,
    qm.activity_sum,
    qm.answers_total,
    qm.max_answer_score,
    qm.avg_answer_score,
    qm.is_closed,
    qm.composite_score,
    row_number() over (order by qm.composite_score desc, qm.ViewCount desc, qm.QScore desc) as rn_overall
  from q_metrics qm
),
q_tag_win as (
  select
    qt.tag,
    qm.QuestionId,
    qm.Title,
    qm.composite_score,
    qm.ViewCount,
    row_number() over (partition by qt.tag order by qm.composite_score desc, qm.ViewCount desc) as rn_by_tag
  from q_metrics qm
  join q_tagged qt on qt.QuestionId = qm.QuestionId
  join top_tags tt on tt.tag = qt.tag
),
q_owner as (
  select
    q.QuestionId,
    u.UserId as OwnerId,
    u.DisplayName as OwnerName,
    u.rep_band as OwnerBand,
    u.Reputation as OwnerRep,
    coalesce(ub.total_badges,0) as OwnerBadges
  from q
  left join u on u.UserId = q.QOwnerId
  left join ub on ub.UserId = q.QOwnerId
),
time_to_accept as (
  select
    q.QuestionId,
    case
      when q.AcceptedAnswerId is null then null
      else (
        select extract(epoch from (a2.ACreated - q.CreationDate))/3600.0
        from a a2
        where a2.AnswerId = q.AcceptedAnswerId
      )
    end as hours_to_accept
  from q
),
q_eng as (
  select
    e.PostId,
    e.upvotes,
    e.downvotes,
    e.favorites,
    e.comments,
    e.high_score_comments,
    e.avg_comment_len,
    e.vote_delta,
    e.activity_sum
  from eng e
  join Posts p on p.Id = e.PostId
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
),
q_activity_stats as (
  select
    qm.QuestionId,
    e.activity_sum
  from q_metrics qm
  left join q_eng e on e.PostId = qm.QuestionId
),
q_activity_dist as (
  select
    percentile_disc(0.5) within group (order by activity_sum) as p50_activity,
    percentile_disc(0.9) within group (order by activity_sum) as p90_activity
  from q_activity_stats
),
q_percentiles as (
  select
    qa.QuestionId,
    qad.p50_activity,
    qad.p90_activity,
    ntile(10) over (order by qm.composite_score) as composite_decile
  from q_activity_stats qa
  cross join q_activity_dist qad
  join q_metrics qm on qm.QuestionId = qa.QuestionId
),
cohort as (
  select
    qm.QuestionId,
    qm.Title,
    qm.CreationDate,
    qm.composite_score,
    qm.ViewCount,
    qm.QScore,
    qm.AnswerCount,
    qm.CommentCount,
    qo.OwnerId,
    qo.OwnerName,
    qo.OwnerBand,
    qo.OwnerRep,
    qo.OwnerBadges,
    ta.hours_to_accept,
    qp.composite_decile,
    qw.rn_overall
  from q_win qw
  join q_metrics qm on qm.QuestionId = qw.QuestionId
  left join q_owner qo on qo.QuestionId = qm.QuestionId
  left join time_to_accept ta on ta.QuestionId = qm.QuestionId
  left join q_percentiles qp on qp.QuestionId = qm.QuestionId
  cross join params prm
  where qm.AnswerCount >= prm.min_answers
)
select
  c.QuestionId,
  coalesce(nullif(c.Title,''), concat('[untitled-', cast(c.QuestionId as text), ']')) as Title,
  c.CreationDate,
  c.OwnerId,
  coalesce(c.OwnerName, '[deleted]') as OwnerName,
  c.OwnerBand,
  c.OwnerRep,
  c.OwnerBadges,
  c.QScore,
  c.ViewCount,
  c.AnswerCount,
  c.CommentCount,
  round(coalesce(c.hours_to_accept, -1)::numeric, 2) as HoursToAccept,
  c.composite_score,
  c.composite_decile,
  c.rn_overall,
  (
    select string_agg(t.tag, ', ' order by t.tag)
    from (
      select distinct lower(trim(t2)) as tag
      from q q2
      cross join lateral unnest(q2.tag_arr) t2
      where q2.QuestionId = c.QuestionId
    ) t
  ) as Tags,
  coalesce((select e.upvotes from eng e where e.PostId = c.QuestionId),0) as Upvotes,
  coalesce((select e.downvotes from eng e where e.PostId = c.QuestionId),0) as Downvotes,
  coalesce((select e.favorites from eng e where e.PostId = c.QuestionId),0) as Favorites,
  coalesce((select e.comments from eng e where e.PostId = c.QuestionId),0) as Comments,
  (select case when cl.first_closed_at is not null then 'Closed' else 'Open' end from closed cl where cl.PostId = c.QuestionId) as CloseState,
  (select cl.last_close_reason_id_text from closed cl where cl.PostId = c.QuestionId) as CloseReasonIdText
from cohort c
where c.rn_overall <= 500
union all
select
  qt.QuestionId,
  coalesce(nullif(qm.Title,''), concat('[untitled-', cast(qt.QuestionId as text), ']')) as Title,
  qm.CreationDate,
  qo.OwnerId,
  coalesce(qo.OwnerName, '[deleted]') as OwnerName,
  qo.OwnerBand,
  qo.OwnerRep,
  qo.OwnerBadges,
  qm.QScore,
  qm.ViewCount,
  qm.AnswerCount,
  qm.CommentCount,
  round(coalesce(ta.hours_to_accept, -1)::numeric, 2) as HoursToAccept,
  qm.composite_score,
  qp.composite_decile,
  100000 + row_number() over (order by qt.tag, qm.composite_score desc) as rn_overall,
  qt.tag as Tags,
  coalesce(e.upvotes,0) as Upvotes,
  coalesce(e.downvotes,0) as Downvotes,
  coalesce(e.favorites,0) as Favorites,
  coalesce(e.comments,0) as Comments,
  case when cl.first_closed_at is not null then 'Closed' else 'Open' end as CloseState,
  cl.last_close_reason_id_text as CloseReasonIdText
from q_tag_win qt
join q_metrics qm on qm.QuestionId = qt.QuestionId
left join q_owner qo on qo.QuestionId = qt.QuestionId
left join time_to_accept ta on ta.QuestionId = qt.QuestionId
left join q_percentiles qp on qp.QuestionId = qt.QuestionId
left join eng e on e.PostId = qt.QuestionId
left join closed cl on cl.PostId = qt.QuestionId
where qt.rn_by_tag <= 3
order by rn_overall, composite_score desc, ViewCount desc;