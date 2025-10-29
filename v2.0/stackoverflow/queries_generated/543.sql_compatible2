with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    count(*) over () as total_users_sampled,
    row_number() over (order by u.reputation desc, u.id) as rn
  from users u
  where u.creationdate >= (select coalesce(max(creationdate), timestamp '1900-01-01') - interval '3 years' from users)
),
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.parentid,
    p.acceptedanswerid,
    p.tags,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer
  from posts p
  where p.creationdate >= (select coalesce(max(creationdate), timestamp '1900-01-01') - interval '3 years' from posts)
),
question_tags as (
  select
    q.id as question_id,
    lower(trim(tg)) as tag
  from recent_posts q
  cross join lateral (
    select unnest(
      case
        when q.is_question = 1 and q.tags is not null and length(q.tags) >= 2
        then string_to_array(substring(q.tags from 2 for length(q.tags)-2), '><')
        else string_to_array('', '')
      end
    )
  ) s(tg)
  where q.is_question = 1
),
badge_rollup as (
  select
    ru.user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(b.id) as total_badges
  from recent_users ru
  left join badges b
    on b.userid = ru.user_id
    and b.date >= cast('2024-10-01' as date) - interval '3 years'
  group by ru.user_id
),
vote_rollup as (
  select
    v.postid,
    v.userid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_flow
  from votes v
  where v.creationdate >= cast('2024-10-01' as date) - interval '3 years'
  group by v.postid, v.userid
),
question_activity as (
  select
    q.id as question_id,
    least(
      coalesce(min(a.creationdate), timestamp '9999-12-31'),
      coalesce(min(c.creationdate), timestamp '9999-12-31'),
      coalesce(min(ph.creationdate), timestamp '9999-12-31')
    ) as first_activity_at
  from recent_posts q
  left join recent_posts a
    on a.parentid = q.id and a.is_answer = 1
  left join comments c
    on c.postid = q.id
  left join posthistory ph
    on ph.postid = q.id and ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36,50,52,53)
  where q.is_question = 1
  group by q.id
),
accept_lag as (
  select
    q.id as question_id,
    case
      when q.acceptedanswerid is null then null
      else (select p2.creationdate from posts p2 where p2.id = q.acceptedanswerid) - q.creationdate
    end as time_to_accept
  from recent_posts q
  where q.is_question = 1
),
duplicate_links as (
  select
    pl.postid as dup_post_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links_out,
    count(*) filter (where pl.linktypeid = 1) as related_links_out
  from postlinks pl
  where pl.creationdate >= cast('2024-10-01' as date) - interval '3 years'
  group by pl.postid
),
user_post_agg as (
  select
    ru.user_id,
    count(*) filter (where rp.is_question = 1) as questions_count,
    count(*) filter (where rp.is_answer = 1) as answers_count,
    avg(nullif(rp.score,0)) filter (where rp.is_question = 1) as avg_q_score_nonzero,
    avg(rp.score) filter (where rp.is_answer = 1) as avg_a_score,
    sum(coalesce(vr.upvotes,0)) as total_upvotes_received,
    sum(coalesce(vr.downvotes,0)) as total_downvotes_received,
    sum(coalesce(vr.favorites,0)) as total_favorites_received,
    sum(coalesce(vr.bounty_flow,0)) as total_bounty_flow_received,
    max(rp.creationdate) as last_post_at,
    min(rp.creationdate) as first_post_at
  from recent_users ru
  left join recent_posts rp on rp.owneruserid = ru.user_id
  left join vote_rollup vr on vr.postid = rp.id
  group by ru.user_id
),
question_level as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as asked_at,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount as q_answers,
    coalesce(al.time_to_accept, interval '0') as time_to_accept_interval,
    case when al.time_to_accept is null then 0 else 1 end as has_accepted,
    qa.first_activity_at,
    extract(epoch from (qa.first_activity_at - q.creationdate))/3600.0 as hours_to_first_activity,
    dl.duplicate_links_out,
    dl.related_links_out
  from recent_posts q
  left join accept_lag al on al.question_id = q.id
  left join question_activity qa on qa.question_id = q.id
  left join duplicate_links dl on dl.dup_post_id = q.id
  where q.is_question = 1
),
user_tag_rank as (
  select
    ql.asker_id as user_id,
    qt.tag,
    count(*) as tag_q_count,
    rank() over (partition by ql.asker_id order by count(*) desc, min(ql.asked_at)) as tag_rank
  from question_level ql
  join question_tags qt on qt.question_id = ql.question_id
  group by ql.asker_id, qt.tag
),
comment_agg as (
  select
    ru.user_id,
    count(c.id) as comments_made,
    avg(c.score) as avg_comment_score,
    sum(case when c.text ilike '%thanks%' or c.text ilike '%great%' or c.text ilike '%awesome%' then 1 else 0 end) as positive_tokens,
    sum(case when c.text ilike '%wtf%' or c.text ilike '%stupid%' or c.text ilike '%dumb%' then 1 else 0 end) as negative_tokens,
    max(c.creationdate) as last_comment_at
  from recent_users ru
  left join comments c on c.userid = ru.user_id and c.creationdate >= cast('2024-10-01' as date) - interval '3 years'
  group by ru.user_id
),
edit_activity as (
  select
    ru.user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    count(*) filter (where ph.posthistorytypeid in (10,35)) as closes_or_migrates,
    max(ph.creationdate) as last_edit_at
  from recent_users ru
  left join posthistory ph on ph.userid = ru.user_id and ph.creationdate >= cast('2024-10-01' as date) - interval '3 years'
  group by ru.user_id
),
cohort_rates as (
  select
    ru.user_id,
    (
      select count(*)
      from posts p
      where p.owneruserid = ru.user_id
        and p.posttypeid = 2
        and p.creationdate < ru.creationdate + interval '90 days'
    ) as answers_first_90d,
    (
      select avg(score)
      from posts p
      where p.owneruserid = ru.user_id and p.posttypeid = 1
    ) as avg_q_score_lifetime,
    (
      select count(distinct pl.relatedpostid)
      from postlinks pl
      join posts q on q.id = pl.postid and q.posttypeid = 1
      where q.owneruserid = ru.user_id and pl.linktypeid = 3
    ) as dup_marked_count
  from recent_users ru
),
user_signals as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location_norm,
    ru.cohort_month,
    ua.questions_count,
    ua.answers_count,
    ua.avg_q_score_nonzero,
    ua.avg_a_score,
    ua.total_upvotes_received,
    ua.total_downvotes_received,
    ua.total_favorites_received,
    ua.total_bounty_flow_received,
    ua.first_post_at,
    ua.last_post_at,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.total_badges,0) as total_badges,
    coalesce(ca.comments_made,0) as comments_made,
    coalesce(ca.avg_comment_score,0) as avg_comment_score,
    coalesce(ca.positive_tokens,0) as positive_tokens,
    coalesce(ca.negative_tokens,0) as negative_tokens,
    ea.edits_made,
    ea.suggested_edits_applied,
    ea.closes_or_migrates,
    cr.answers_first_90d,
    cr.avg_q_score_lifetime,
    cr.dup_marked_count,
    greatest(
      coalesce(ua.last_post_at, timestamp '1900-01-01'),
      coalesce(ca.last_comment_at, timestamp '1900-01-01'),
      coalesce(ea.last_edit_at, timestamp '1900-01-01')
    ) as last_activity_any
  from recent_users ru
  left join user_post_agg ua on ua.user_id = ru.user_id
  left join badge_rollup ba on ba.user_id = ru.user_id
  left join comment_agg ca on ca.user_id = ru.user_id
  left join edit_activity ea on ea.user_id = ru.user_id
  left join cohort_rates cr on cr.user_id = ru.user_id
),
user_with_top_tag as (
  select
    us.*,
    ut.tag as top_tag,
    ut.tag_q_count as top_tag_q_count
  from user_signals us
  left join lateral (
    select tag, tag_q_count
    from user_tag_rank utr
    where utr.user_id = us.user_id and utr.tag_rank = 1
    order by tag asc
    limit 1
  ) ut on true
),
scored_users as (
  select
    u.*,
    (
      coalesce(u.reputation,0)/100.0
      + coalesce(u.total_upvotes_received,0)*0.5
      - coalesce(u.total_downvotes_received,0)*0.75
      + coalesce(u.total_favorites_received,0)*0.25
      + coalesce(u.gold_badges,0)*5
      + coalesce(u.silver_badges,0)*2
      + coalesce(u.bronze_badges,0)*1
      + coalesce(u.answers_count,0)*0.6
      + coalesce(u.questions_count,0)*0.4
      + least(coalesce(u.avg_q_score_nonzero,0), 10)*1.2
      + least(coalesce(u.avg_a_score,0), 10)*1.0
      - coalesce(u.dup_marked_count,0)*2.0
      + coalesce(u.suggested_edits_applied,0)*0.3
      + case when coalesce(u.negative_tokens,0) > coalesce(u.positive_tokens,0) then -1 else 0 end
    ) as composite_score,
    dense_rank() over (order by
      (
        coalesce(u.reputation,0)/100.0
        + coalesce(u.total_upvotes_received,0)*0.5
        - coalesce(u.total_downvotes_received,0)*0.75
        + coalesce(u.total_favorites_received,0)*0.25
        + coalesce(u.gold_badges,0)*5
        + coalesce(u.silver_badges,0)*2
        + coalesce(u.bronze_badges,0)*1
        + coalesce(u.answers_count,0)*0.6
        + coalesce(u.questions_count,0)*0.4
        + least(coalesce(u.avg_q_score_nonzero,0), 10)*1.2
        + least(coalesce(u.avg_a_score,0), 10)*1.0
        - coalesce(u.dup_marked_count,0)*2.0
        + coalesce(u.suggested_edits_applied,0)*0.3
        + case when coalesce(u.negative_tokens,0) > coalesce(u.positive_tokens,0) then -1 else 0 end
      ) desc, u.user_id
    ) as score_rank,
    ntile(100) over (order by coalesce(u.reputation,0) desc, u.user_id) as reputation_percentile
  from user_with_top_tag u
),
outlier_questions as (
  select
    ql.*,
    case
      when ql.hours_to_first_activity is null then 1
      when ql.hours_to_first_activity > 24*14 then 1
      when ql.has_accepted = 0 and (timestamp '2024-10-01 12:34:56' - ql.asked_at) > interval '180 days' then 1
      else 0
    end as is_outlier
  from question_level ql
),
user_outlier_stats as (
  select
    oq.asker_id as user_id,
    count(*) filter (where oq.is_outlier = 1) as outlier_questions,
    avg(oq.hours_to_first_activity) as avg_hours_to_first_activity,
    avg(case when oq.has_accepted = 1 then extract(epoch from oq.time_to_accept_interval)/3600.0 end) as avg_hours_to_accept
  from outlier_questions oq
  group by oq.asker_id
),
final_dataset as (
  select
    su.user_id,
    coalesce(nullif(su.displayname, ''), '<unknown>') as display_name,
    su.location_norm,
    coalesce(su.top_tag, '<no-tag>') as top_tag,
    su.top_tag_q_count,
    su.reputation,
    su.cohort_month,
    su.questions_count,
    su.answers_count,
    su.gold_badges,
    su.silver_badges,
    su.bronze_badges,
    su.total_badges,
    su.total_upvotes_received,
    su.total_downvotes_received,
    su.total_favorites_received,
    su.total_bounty_flow_received,
    su.first_post_at,
    su.last_post_at,
    su.last_activity_any,
    su.comments_made,
    su.avg_comment_score,
    su.positive_tokens,
    su.negative_tokens,
    su.answers_first_90d,
    su.avg_q_score_lifetime,
    su.dup_marked_count,
    su.composite_score,
    su.score_rank,
    su.reputation_percentile,
    uos.outlier_questions,
    uos.avg_hours_to_first_activity,
    uos.avg_hours_to_accept,
    trim(both ' ' from concat_ws(' | ',
      case
        when su.reputation_percentile <= 5 then 'ELITE'
        when su.reputation_percentile <= 20 then 'ADVANCED'
        when su.reputation_percentile <= 50 then 'INTERMEDIATE'
        else 'NOVICE'
      end,
      case when su.top_tag is null then 'UNTAGGED' else upper(su.top_tag) end,
      case when su.gold_badges > 0 then concat(su.gold_badges, 'xG') end,
      case when su.silver_badges > 0 then concat(su.silver_badges, 'xS') end,
      case when su.bronze_badges > 0 then concat(su.bronze_badges, 'xB') end
    )) as user_label
  from scored_users su
  left join user_outlier_stats uos on uos.user_id = su.user_id
),
bench_set as (
  select user_id, 'HIGH_BOUNTY' as flag
  from final_dataset
  where total_bounty_flow_received >= (
    select percentile_cont(0.95) within group (order by coalesce(total_bounty_flow_received,0))
    from final_dataset
  )
  union all
  select user_id, 'DUPLICATE_PRONE' as flag
  from final_dataset
  where dup_marked_count >= 3
  union
  select user_id, 'OUTLIER_AUTHOR' as flag
  from final_dataset
  where coalesce(outlier_questions,0) > 0
)
select
  fd.user_id,
  fd.display_name,
  fd.user_label,
  fd.location_norm,
  fd.top_tag,
  fd.top_tag_q_count,
  fd.reputation,
  fd.cohort_month,
  fd.questions_count,
  fd.answers_count,
  fd.total_badges,
  fd.total_upvotes_received,
  fd.total_downvotes_received,
  fd.total_favorites_received,
  fd.total_bounty_flow_received,
  fd.first_post_at,
  fd.last_post_at,
  fd.last_activity_any,
  fd.comments_made,
  fd.avg_comment_score,
  fd.answers_first_90d,
  fd.avg_q_score_lifetime,
  fd.dup_marked_count,
  fd.outlier_questions,
  fd.avg_hours_to_first_activity,
  fd.avg_hours_to_accept,
  fd.composite_score,
  fd.score_rank,
  fd.reputation_percentile,
  (select count(*) from bench_set bs where bs.user_id = fd.user_id) as bench_flags_count,
  string_agg(bs.flag, ',' order by bs.flag) filter (where bs.flag is not null) as flags
from final_dataset fd
left join bench_set bs on bs.user_id = fd.user_id
where
  coalesce(fd.questions_count,0) + coalesce(fd.answers_count,0) >= 3
  and (
    fd.reputation_percentile <= 50
    or (fd.total_badges >= 5 and coalesce(fd.avg_q_score_lifetime,0) >= 0)
    or fd.dup_marked_count is null
  )
group by
  fd.user_id, fd.display_name, fd.user_label, fd.location_norm, fd.top_tag, fd.top_tag_q_count,
  fd.reputation, fd.cohort_month, fd.questions_count, fd.answers_count, fd.total_badges,
  fd.total_upvotes_received, fd.total_downvotes_received, fd.total_favorites_received,
  fd.total_bounty_flow_received, fd.first_post_at, fd.last_post_at, fd.last_activity_any,
  fd.comments_made, fd.avg_comment_score, fd.answers_first_90d, fd.avg_q_score_lifetime,
  fd.dup_marked_count, fd.outlier_questions, fd.avg_hours_to_first_activity, fd.avg_hours_to_accept,
  fd.composite_score, fd.score_rank, fd.reputation_percentile
order by
  fd.score_rank,
  fd.user_id
limit 500;