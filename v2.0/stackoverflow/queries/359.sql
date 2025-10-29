-- {"query": "359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3124}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(b.id) as total_badges,
    row_number() over (order by u.reputation desc, u.id) as rn_rep
  from users u
  left join badges b
    on b.userid = u.id
   and b.date >= u.creationdate
  where u.creationdate >= (select min(creationdate) from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
question_posts as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.title,
    p.tags,
    coalesce(p.commentcount, 0) as commentcount,
    case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    p.id as post_id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score
  from posts p
  where p.posttypeid = 2
),
question_activity as (
  select
    q.post_id,
    q.user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.commentcount,
    q.title,
    q.tags,
    q.is_closed,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
    count(distinct c.id) as comments,
    count(distinct a.post_id) as answers_total,
    max(a.score) as best_answer_score
  from question_posts q
  left join votes v
    on v.postid = q.post_id
  left join comments c
    on c.postid = q.post_id
  left join answer_posts a
    on a.question_id = q.post_id
  group by q.post_id, q.user_id, q.creationdate, q.score, q.viewcount, q.answercount, q.favoritecount, q.commentcount, q.title, q.tags, q.is_closed
),
user_q_agg as (
  select
    qa.user_id,
    count(*) as total_questions,
    sum(case when qa.is_closed = 1 then 1 else 0 end) as closed_questions,
    sum(qa.upvotes) as upvotes_on_questions,
    sum(qa.downvotes) as downvotes_on_questions,
    sum(qa.viewcount) as total_views,
    avg(nullif(qa.answercount,0)) as avg_answers_reported,
    avg(qa.score) as avg_q_score,
    percentile_cont(0.9) within group (order by qa.score) as p90_q_score,
    max(qa.best_answer_score) as max_best_answer_score
  from question_activity qa
  group by qa.user_id
),
user_a_agg as (
  select
    a.user_id,
    count(*) as total_answers,
    sum(a.score) as sum_answer_score,
    avg(a.score) as avg_answer_score,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers
  from answer_posts a
  group by a.user_id
),
tag_exploded as (
  select
    q.post_id,
    lower(trim(tg)) as tag_name
  from question_posts q
  cross join lateral unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as t(tg)
),
top_tags as (
  select
    te.tag_name,
    count(*) as tag_usage
  from tag_exploded te
  group by te.tag_name
  having count(*) > 10
),
user_tag_pref as (
  select
    qa.user_id,
    te.tag_name,
    count(*) as tag_count,
    row_number() over (partition by qa.user_id order by count(*) desc, min(qa.creationdate)) as tag_rank
  from question_activity qa
  join tag_exploded te on te.post_id = qa.post_id
  group by qa.user_id, te.tag_name
),
recent_closures as (
  select
    ph.postid,
    max(ph.creationdate) as last_close_date,
    max(case when ph.posthistorytypeid = 10 then nullif(ph.comment,'') end) as last_close_reason_text,
    max(case when ph.posthistorytypeid = 10 and nullif(ph.comment,'') ~ '^[0-9]+$' then cast(nullif(ph.comment,'') as integer) end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
dup_links as (
  select pl.postid as dup_post_id, pl.relatedpostid as original_post_id
  from postlinks pl
  where pl.linktypeid = 3
),
hot_spikes as (
  select
    qa.post_id,
    qa.user_id,
    cast(qa.creationdate as date) as day,
    qa.viewcount,
    qa.score,
    lag(qa.viewcount) over (partition by qa.user_id order by qa.creationdate) as prev_views,
    case
      when lag(qa.viewcount) over (partition by qa.user_id order by qa.creationdate) is null then 0
      else qa.viewcount - lag(qa.viewcount) over (partition by qa.user_id order by qa.creationdate)
    end as view_delta
  from question_activity qa
),
user_hotness as (
  select
    user_id,
    max(view_delta) as max_view_spike,
    avg(view_delta) as avg_view_delta
  from hot_spikes
  group by user_id
),
ranked_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.total_badges,
    coalesce(uq.total_questions,0) as total_questions,
    coalesce(uq.closed_questions,0) as closed_questions,
    coalesce(uq.upvotes_on_questions,0) as upvotes_on_questions,
    coalesce(uq.downvotes_on_questions,0) as downvotes_on_questions,
    coalesce(uq.total_views,0) as total_views,
    uq.avg_answers_reported,
    uq.avg_q_score,
    uq.p90_q_score,
    uq.max_best_answer_score,
    coalesce(ua.total_answers,0) as total_answers,
    coalesce(ua.sum_answer_score,0) as sum_answer_score,
    ua.avg_answer_score,
    coalesce(ua.positive_answers,0) as positive_answers,
    coalesce(uh.max_view_spike,0) as max_view_spike,
    coalesce(uh.avg_view_delta,0) as avg_view_delta,
    nt.tag_name as top_tag,
    case when ru.reputation >= 200000 then 'legend'
         when ru.reputation >= 50000 then 'veteran'
         when ru.reputation >= 10000 then 'seasoned'
         when ru.reputation >= 2000 then 'active'
         else 'newbie'
    end as rep_bucket,
    row_number() over (
      order by
        coalesce(uq.upvotes_on_questions,0) + coalesce(ua.sum_answer_score,0) + ru.reputation/100.0 desc,
        coalesce(uq.total_views,0) desc,
        coalesce(ru.user_id,0)
    ) as global_rank
  from recent_users ru
  left join user_q_agg uq on uq.user_id = ru.user_id
  left join user_a_agg ua on ua.user_id = ru.user_id
  left join user_hotness uh on uh.user_id = ru.user_id
  left join lateral (
    select ut.tag_name
    from user_tag_pref ut
    join top_tags tt on tt.tag_name = ut.tag_name
    where ut.user_id = ru.user_id
    order by ut.tag_rank
    limit 1
  ) nt on true
),
closed_breakdown as (
  select
    p.owneruserid as user_id,
    crt.name as close_reason_name,
    count(*) as closes_by_reason
  from posts p
  join recent_closures rc on rc.postid = p.id
  left join closereasontypes crt on crt.id = rc.last_close_reason_id
  group by p.owneruserid, crt.name
),
closed_pivot as (
  select
    user_id,
    sum(case when coalesce(close_reason_name, 'Unknown') = 'Duplicate' then closes_by_reason else 0 end) as closes_duplicate,
    sum(case when coalesce(close_reason_name, 'Unknown') = 'Off-topic' then closes_by_reason else 0 end) as closes_offtopic,
    sum(case when coalesce(close_reason_name, 'Unknown') = 'Needs details or clarity' then closes_by_reason else 0 end) as closes_needs_clarity,
    sum(case when coalesce(close_reason_name, 'Unknown') = 'Needs more focus' then closes_by_reason else 0 end) as closes_needs_focus,
    sum(case when coalesce(close_reason_name, 'Unknown') = 'Opinion-based' then closes_by_reason else 0 end) as closes_opinion,
    sum(case when close_reason_name is null then closes_by_reason else 0 end) as closes_unknown
  from closed_breakdown
  group by user_id
),
dup_stats as (
  select
    p.owneruserid as user_id,
    count(distinct d.dup_post_id) as duplicates_marked,
    count(distinct d.original_post_id) as originals_referenced
  from posts p
  join dup_links d on d.dup_post_id = p.id
  group by p.owneruserid
),
activity_window as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.creationdate,
    sum(p.score) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as running_user_score,
    count(*) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as running_post_count
  from posts p
  where p.posttypeid in (1,2)
),
user_activity_bursts as (
  select
    user_id,
    max(running_post_count) as max_post_seq,
    max(running_user_score) as max_running_score
  from activity_window
  group by user_id
),
final_rank as (
  select
    r.*,
    coalesce(cp.closes_duplicate,0) as closes_duplicate,
    coalesce(cp.closes_offtopic,0) as closes_offtopic,
    coalesce(cp.closes_needs_clarity,0) as closes_needs_clarity,
    coalesce(cp.closes_needs_focus,0) as closes_needs_focus,
    coalesce(cp.closes_opinion,0) as closes_opinion,
    coalesce(cp.closes_unknown,0) as closes_unknown,
    coalesce(ds.duplicates_marked,0) as duplicates_marked,
    coalesce(ds.originals_referenced,0) as originals_referenced,
    coalesce(ub.max_post_seq,0) as max_post_seq,
    coalesce(ub.max_running_score,0) as max_running_score,
    case
      when coalesce(r.total_questions,0) = 0 then null
      else round(cast(coalesce(r.closed_questions,0) as numeric) / nullif(r.total_questions,0), 4)
    end as close_rate
  from ranked_users r
  left join closed_pivot cp on cp.user_id = r.user_id
  left join dup_stats ds on ds.user_id = r.user_id
  left join user_activity_bursts ub on ub.user_id = r.user_id
),
top_and_bottom as (
  select *
  from (
    select *, row_number() over (order by global_rank) as rn_asc, row_number() over (order by global_rank desc) as rn_desc
    from final_rank
  ) t
  where rn_asc <= 100 or rn_desc <= 100
),
stringified as (
  select
    user_id,
    coalesce(displayname, '(unknown)') as displayname,
    reputation,
    rep_bucket,
    global_rank,
    total_questions,
    total_answers,
    total_views,
    upvotes_on_questions,
    sum_answer_score,
    coalesce(top_tag, '(no tag)') as top_tag,
    closes_duplicate + closes_offtopic + closes_needs_clarity + closes_needs_focus + closes_opinion + closes_unknown as total_closes,
    concat(
      'UserId=', user_id, ' | ',
      'Name=', coalesce(nullif(displayname,''), '(unknown)'), ' | ',
      'Rep=', reputation, ' | ',
      'Rank=', global_rank, ' | ',
      'TopTag=', coalesce(top_tag,'(no tag)'), ' | ',
      'Q=', coalesce(total_questions,0), ' | ',
      'A=', coalesce(total_answers,0), ' | ',
      'Views=', coalesce(total_views,0), ' | ',
      'UpQ=', coalesce(upvotes_on_questions,0), ' | ',
      'SumA=', coalesce(sum_answer_score,0), ' | ',
      'Closes=', (closes_duplicate + closes_offtopic + closes_needs_clarity + closes_needs_focus + closes_opinion + closes_unknown), ' | ',
      'CloseRate=', coalesce(close_rate,0)
    ) as summary
  from top_and_bottom
)
select
  s.user_id,
  s.displayname,
  s.reputation,
  s.rep_bucket,
  s.global_rank,
  s.total_questions,
  s.total_answers,
  s.total_views,
  s.upvotes_on_questions,
  s.sum_answer_score,
  s.top_tag,
  s.total_closes,
  s.summary
from stringified s
order by s.global_rank, s.user_id;