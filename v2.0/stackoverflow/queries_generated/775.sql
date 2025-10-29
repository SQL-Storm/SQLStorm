-- {"query": "775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4043} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.location,
         u.creationdate,
         u.lastaccessdate,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 1)), ''), 'unknown') as site_host_guess
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select p.id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.favoritecount,
         p.closeddate,
         p.communityowneddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select a.id,
         a.parentid as question_id,
         a.owneruserid,
         a.creationdate,
         a.score
  from posts a
  where a.posttypeid = 2
),
user_activity as (
  select ru.user_id,
         count(distinct qp.id) filter (where qp.id is not null) as questions_asked,
         count(distinct ap.id) filter (where ap.id is not null) as answers_posted,
         count(distinct c.id) filter (where c.id is not null) as comments_made,
         count(distinct v.id) filter (where v.id is not null and v.votetypeid = 2) as upvotes_cast,
         count(distinct v.id) filter (where v.id is not null and v.votetypeid = 3) as downvotes_cast,
         sum(coalesce(qp.score,0)) as question_score_sum,
         sum(coalesce(ap.score,0)) as answer_score_sum,
         sum(coalesce(c.score,0)) as comment_score_sum
  from recent_users ru
  left join question_posts qp on qp.owneruserid = ru.user_id
  left join answer_posts ap on ap.owneruserid = ru.user_id
  left join comments c on c.userid = ru.user_id
  left join votes v on v.userid = ru.user_id
  group by ru.user_id
),
question_enrichment as (
  select
    qp.id as question_id,
    qp.owneruserid as asker_id,
    qp.creationdate,
    qp.score,
    qp.viewcount,
    qp.answercount,
    qp.favoritecount,
    qp.closeddate,
    qp.communityowneddate,
    qp.title,
    qp.tags,
    -- extract primary tag as first element between <>
    nullif(trim((string_to_array(substring(coalesce(qp.tags, ''), 2, greatest(length(coalesce(qp.tags,'')) - 2, 0)), '><'))[1])) as primary_tag,
    -- average answer score and time-to-first-answer
    count(ap.id) as answers_total,
    avg(ap.score::numeric) as avg_answer_score,
    min(ap.creationdate) filter (where ap.id is not null) as first_answer_time,
    extract(epoch from (min(ap.creationdate) filter (where ap.id is not null) - qp.creationdate)) as seconds_to_first_answer,
    -- accepted answer presence via self-join on posts
    case when exists (
      select 1
      from posts aa
      where aa.id = qp.acceptedanswerid
    ) then 1 else 0 end as has_accepted_answer,
    -- close reason if present in PostHistory (most recent close)
    (
      select crt.name
      from posthistory ph
      join closerreasontypes crt
        on crt.id = nullif(ph.comment, '')::smallint
      where ph.postid = qp.id
        and ph.posthistorytypeid = 10
      order by ph.creationdate desc
      limit 1
    ) as close_reason_name
  from question_posts qp
  left join answer_posts ap on ap.question_id = qp.id
  group by qp.id, qp.owneruserid, qp.creationdate, qp.score, qp.viewcount, qp.answercount, qp.favoritecount, qp.closeddate, qp.communityowneddate, qp.title, qp.tags, qp.acceptedanswerid
),
hot_question_flags as (
  select
    qe.question_id,
    max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as was_hot,
    max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_from_hot
  from question_enrichment qe
  left join posthistory ph
    on ph.postid = qe.question_id
   and ph.posthistorytypeid in (52,53)
  group by qe.question_id
),
tag_stats as (
  select
    lower(t.tagname) as tagname,
    sum(t.count) as tag_total_count,
    count(*) as tag_rows,
    sum(case when coalesce(t.ismoderatoronly, 0) = 1 then 1 else 0 end) as moderator_only_count,
    sum(case when coalesce(t.isrequired, 0) = 1 then 1 else 0 end) as required_count
  from tags t
  group by lower(t.tagname)
),
question_tag_assoc as (
  select
    qe.question_id,
    unnest(string_to_array(substring(coalesce(qe.tags, ''), 2, greatest(length(coalesce(qe.tags,'')) - 2, 0)), '><')) as tagname
  from question_enrichment qe
),
question_tag_rank as (
  select
    qta.question_id,
    lower(qta.tagname) as tagname,
    row_number() over (partition by qta.question_id order by lower(qta.tagname)) as tag_order,
    count(*) over (partition by qta.question_id) as tag_count
  from question_tag_assoc qta
),
user_badge_summary as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    sum(case when coalesce(b.tagbased,0) = 1 then 1 else 0 end) as tag_badges,
    count(*) as total_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_vote_agg as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid
),
question_comment_agg as (
  select
    c.postid as question_id,
    count(*) as comment_count,
    avg(coalesce(c.score,0)::numeric) as avg_comment_score,
    max(length(c.text)) as max_comment_len,
    sum(case when c.userid is null then 1 else 0 end) as anon_comments
  from comments c
  group by c.postid
),
dup_graph as (
  select
    pl.postid as duplicate_id,
    pl.relatedpostid as original_id,
    pl.creationdate as link_time
  from postlinks pl
  where pl.linktypeid = 3
),
dup_cluster as (
  select
    dg.duplicate_id,
    dg.original_id,
    least(dg.duplicate_id, dg.original_id) as cluster_key
  from dup_graph dg
),
final_questions as (
  select
    qe.question_id,
    qe.asker_id,
    qe.creationdate,
    qe.title,
    qe.primary_tag,
    coalesce(qe.close_reason_name, 'Open') as close_reason_name,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.favoritecount,
    qe.seconds_to_first_answer,
    qe.has_accepted_answer,
    hq.was_hot,
    hq.removed_from_hot,
    t.tag_total_count,
    t.moderator_only_count,
    t.required_count,
    qv.upvotes,
    qv.downvotes,
    qv.favorites_legacy,
    qv.bounty_total,
    qc.comment_count,
    qc.avg_comment_score,
    qc.max_comment_len,
    qc.anon_comments,
    dc.cluster_key as dup_cluster_key
  from question_enrichment qe
  left join hot_question_flags hq on hq.question_id = qe.question_id
  left join tag_stats t on t.tagname = lower(coalesce(qe.primary_tag, ''))
  left join question_vote_agg qv on qv.question_id = qe.question_id
  left join question_comment_agg qc on qc.question_id = qe.question_id
  left join dup_cluster dc on dc.duplicate_id = qe.question_id
),
scored_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.creationdate,
    ru.lastaccessdate,
    ru.site_host_guess,
    ua.questions_asked,
    ua.answers_posted,
    ua.comments_made,
    ua.upvotes_cast,
    ua.downvotes_cast,
    ua.question_score_sum,
    ua.answer_score_sum,
    ua.comment_score_sum,
    coalesce(ubs.gold,0) as gold,
    coalesce(ubs.silver,0) as silver,
    coalesce(ubs.bronze,0) as bronze,
    coalesce(ubs.tag_badges,0) as tag_badges,
    coalesce(ubs.total_badges,0) as total_badges,
    ubs.first_badge_date,
    ubs.last_badge_date,
    -- engagement score with non-linear pieces and null handling
    (
      greatest(ua.questions_asked,0) * 3
      + greatest(ua.answers_posted,0) * 5
      + greatest(ua.comments_made,0) * 1
      + coalesce(ua.question_score_sum,0) * 2
      + coalesce(ua.answer_score_sum,0) * 4
      + coalesce(ua.comment_score_sum,0) * 0.5
      + least(coalesce(ubs.total_badges,0), 50)
      - greatest(coalesce(ua.downvotes_cast,0) - coalesce(ua.upvotes_cast,0), 0)
    )::numeric as engagement_score
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_badge_summary ubs on ubs.userid = ru.user_id
),
user_question_rollup as (
  select
    fq.asker_id as user_id,
    count(*) as questions_total,
    avg(fq.score::numeric) as avg_q_score,
    avg(fq.viewcount::numeric) as avg_q_views,
    sum(case when fq.has_accepted_answer = 1 then 1 else 0 end) as accepted_count,
    sum(case when fq.close_reason_name <> 'Open' then 1 else 0 end) as closed_count,
    sum(coalesce(fq.upvotes,0)) as q_upvotes_rcvd,
    sum(coalesce(fq.downvotes,0)) as q_downvotes_rcvd,
    sum(coalesce(fq.bounty_total,0)) as q_bounty_total,
    max(fq.creationdate) as last_question_time
  from final_questions fq
  group by fq.asker_id
),
user_answer_rollup as (
  select
    ap.owneruserid as user_id,
    count(*) as answers_total,
    avg(ap.score::numeric) as avg_a_score,
    max(ap.creationdate) as last_answer_time
  from answer_posts ap
  group by ap.owneruserid
),
recent_quality_questions as (
  select
    fq.*,
    row_number() over (
      partition by fq.primary_tag
      order by (fq.score + coalesce(fq.upvotes,0) - coalesce(fq.downvotes,0)) desc nulls last,
               fq.viewcount desc nulls last
    ) as tag_rank
  from final_questions fq
  where fq.creationdate >= (select max(creationdate) - interval '180 days' from posts)
    and coalesce(fq.close_reason_name, 'Open') = 'Open'
),
top_recent_per_tag as (
  select *
  from recent_quality_questions
  where tag_rank <= 5
),
heavy_users as (
  select
    su.user_id,
    su.displayname,
    su.reputation,
    su.location,
    su.engagement_score,
    coalesce(uqr.questions_total,0) as questions_total,
    coalesce(uar.answers_total,0) as answers_total,
    coalesce(uqr.accepted_count,0) as accepted_questions,
    coalesce(uqr.closed_count,0) as closed_questions,
    coalesce(uqr.q_bounty_total,0) as bounty_earned_on_questions,
    greatest(coalesce(uqr.last_question_time, timestamp 'epoch'),
             coalesce(uar.last_answer_time, timestamp 'epoch')) as last_post_time
  from scored_users su
  left join user_question_rollup uqr on uqr.user_id = su.user_id
  left join user_answer_rollup uar on uar.user_id = su.user_id
  where coalesce(uqr.questions_total,0) + coalesce(uar.answers_total,0) >= 10
),
post_edit_activity as (
  select
    p.id as post_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_count,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_time,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_time,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied
  from posts p
  left join posthistory ph on ph.postid = p.id
  group by p.id
),
user_recentness as (
  select
    su.user_id,
    case
      when su.lastaccessdate >= now() - interval '7 days' then 'active_7d'
      when su.lastaccessdate >= now() - interval '30 days' then 'active_30d'
      when su.lastaccessdate >= now() - interval '90 days' then 'active_90d'
      else 'inactive_90d_plus'
    end as activity_bucket
  from scored_users su
),
final_union as (
  select
    'question'::text as entity_type,
    fq.question_id::text as entity_id,
    fq.creationdate,
    fq.title as headline,
    fq.primary_tag as group_key,
    fq.score,
    fq.viewcount as metric_one,
    coalesce(fq.upvotes,0) - coalesce(fq.downvotes,0) as metric_two,
    fq.has_accepted_answer as flag_one,
    fq.was_hot as flag_two,
    fq.close_reason_name as status_text,
    json_build_object(
      'seconds_to_first_answer', fq.seconds_to_first_answer,
      'bounty_total', fq.bounty_total,
      'dup_cluster_key', fq.dup_cluster_key,
      'comment_count', fq.comment_count
    ) as extra_json
  from top_recent_per_tag fq
  union all
  select
    'user'::text as entity_type,
    hu.user_id::text as entity_id,
    hu.last_post_time as creationdate,
    coalesce(nullif(hu.displayname,''),'[unknown]') as headline,
    coalesce(nullif(trim(split_part(coalesce(hu.location,''), ',', 1)),''), 'nowhere') as group_key,
    hu.reputation as score,
    hu.questions_total as metric_one,
    hu.answers_total as metric_two,
    case when hu.engagement_score > 100 then 1 else 0 end as flag_one,
    case when hu.closed_questions = 0 then 1 else 0 end as flag_two,
    ur.activity_bucket as status_text,
    json_build_object(
      'accepted_questions', hu.accepted_questions,
      'bounty_earned_on_questions', hu.bounty_earned_on_questions,
      'engagement_score', hu.engagement_score
    ) as extra_json
  from heavy_users hu
  left join user_recentness ur on ur.user_id = hu.user_id
)
select
  fu.entity_type,
  fu.entity_id,
  fu.creationdate,
  fu.headline,
  fu.group_key,
  fu.score,
  fu.metric_one,
  fu.metric_two,
  fu.flag_one,
  fu.flag_two,
  fu.status_text,
  fu.extra_json,
  -- window ranks and percentiles for benchmarking
  row_number() over (partition by fu.entity_type order by fu.score desc nulls last, fu.creationdate desc) as rn_by_type,
  rank() over (order by fu.metric_one desc nulls last) as rk_metric_one,
  dense_rank() over (order by fu.metric_two desc nulls last) as dr_metric_two,
  percent_rank() over (partition by fu.entity_type order by fu.score) as pct_score_within_type,
  cume_dist() over (order by (coalesce(fu.metric_one,0) + coalesce(fu.metric_two,0))) as cd_total_metric,
  -- complex predicate evaluation as materialized boolean
  case
    when fu.entity_type = 'question'
     and (coalesce((fu.extra_json->>'bounty_total')::int,0) > 0
          or coalesce((fu.extra_json->>'comment_count')::int,0) > 10)
     and fu.score >= 0 then 1
    when fu.entity_type = 'user'
     and (fu.flag_one = 1 and fu.metric_two > fu.metric_one) then 1
    else 0
  end as interesting_flag
from final_union fu
where (
    fu.entity_type = 'question'
    and (
      fu.score >= 5
      or (coalesce((fu.extra_json->>'seconds_to_first_answer')::numeric, 1e9) < 3600 and fu.metric_two >= 0)
    )
  )
  or (
    fu.entity_type = 'user'
    and (
      fu.score >= 1000
      or (fu.flag_one = 1 and fu.flag_two = 1)
    )
  )
order by fu.entity_type, rn_by_type
limit 500;