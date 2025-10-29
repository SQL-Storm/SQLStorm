-- {"query": "404.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3121}
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(split_part(u.location, ',', 1)), ''), 'Unknown') as home_region,
         u.upvotes,
         u.downvotes,
         date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
qa as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.title,
         p.tags,
         (p.posttypeid = 1) as is_question,
         (p.posttypeid = 2) as is_answer,
         case when p.tags is not null and length(p.tags) >= 2
              then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
              else null
         end as tag_array
  from posts p
  where p.posttypeid in (1,2)
),
q_tags as (
  select q.id as post_id,
         lower(trim(t.tag_name)) as tag_name
  from qa q
  left join lateral (
    select unnest_val as tag_name
    from unnest(coalesce(q.tag_array, array[]::text[])) as unnest_val
  ) t on true
  where q.is_question
),
tag_rank as (
  select qt.tag_name,
         count(*) as q_count,
         dense_rank() over (order by count(*) desc, qt.tag_name) as pop_rank
  from q_tags qt
  group by qt.tag_name
),
user_activity as (
  select ru.user_id,
         date_trunc('month', qa.creationdate) as month,
         sum(case when qa.is_question then 1 else 0 end) as questions,
         sum(case when qa.is_answer then 1 else 0 end) as answers,
         sum(coalesce(qa.score,0)) as total_score,
         sum(coalesce(qa.viewcount,0)) filter (where qa.is_question) as question_views
  from recent_users ru
  left join qa on qa.owneruserid = ru.user_id
    and qa.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by ru.user_id, date_trunc('month', qa.creationdate)
),
user_activity_win as (
  select ua.user_id,
         ua.month,
         ua.questions,
         ua.answers,
         ua.total_score,
         sum(ua.questions) over (partition by ua.user_id order by ua.month rows between 2 preceding and current row) as q_last3m,
         sum(ua.answers)   over (partition by ua.user_id order by ua.month rows between 2 preceding and current row) as a_last3m,
         sum(ua.total_score) over (partition by ua.user_id order by ua.month rows between 2 preceding and current row) as score_last3m
  from user_activity ua
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
         count(*) as vote_events
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comments,
         avg(nullif(length(c.text),0)) as avg_comment_len,
         max(c.creationdate) as last_comment_at,
         sum(case when position('thanks' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end) as thank_comments
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by c.postid
),
link_agg as (
  select pl.postid,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links,
         count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
  from postlinks pl
  where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
  group by pl.postid
),
history_agg as (
  select ph.postid,
         sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_events,
         sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
         sum(case when ph.posthistorytypeid in (4,5,6,24) then 1 else 0 end) as edit_events,
         max(case when ph.posthistorytypeid in (10,35) then ph.creationdate end) as last_close_at,
         max(ph.creationdate) as last_hist_at
  from posthistory ph
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
  group by ph.postid
),
badge_recent as (
  select b.userid,
         min(b.date) filter (where b.class = 1) as first_gold_at,
         max(b.date) filter (where b.class = 1) as last_gold_at,
         count(*) filter (where b.class = 1) as golds,
         count(*) filter (where b.class = 2) as silvers,
         count(*) filter (where b.class = 3) as bronzes
  from badges b
  where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by b.userid
),
question_core as (
  select q.id as question_id,
         q.owneruserid as owner_user_id,
         q.creationdate,
         q.title,
         coalesce(q.score,0) as score,
         coalesce(q.viewcount,0) as views,
         coalesce(q.answercount,0) as answers,
         va.upvotes,
         va.downvotes,
         va.bounty_total,
         coalesce(ca.comments,0) as comments,
         ca.avg_comment_len,
         la.duplicate_links,
         la.related_links,
         la.distinct_dupe_targets,
         ha.close_events,
         ha.reopen_events,
         ha.edit_events,
         ha.last_close_at,
         ha.last_hist_at,
         case when q.tag_array is not null then array_length(q.tag_array,1) else 0 end as tag_count,
         q.tags,
         q.tag_array
  from qa q
  left join vote_agg va on va.postid = q.id
  left join comment_agg ca on ca.postid = q.id
  left join link_agg la on la.postid = q.id
  left join history_agg ha on ha.postid = q.id
  where q.is_question
),
question_tag_rank as (
  select qc.question_id,
         min(s.pop_rank) as best_tag_rank,
         max(s.pop_rank) as worst_tag_rank
  from question_core qc
  left join lateral (
    select tr.pop_rank
    from unnest(coalesce(qc.tag_array, array[]::text[])) as t(tag_name)
    join tag_rank tr on tr.tag_name = lower(t.tag_name)
  ) s on true
  group by qc.question_id
),
question_scored as (
  select qc.*,
         qtr.best_tag_rank,
         qtr.worst_tag_rank,
         (
           coalesce(qc.score,0)*2
           + coalesce(qc.upvotes,0)
           - coalesce(qc.downvotes,0)*1.5
           + ln(1 + qc.views)
           + coalesce(qc.bounty_total,0) / 50.0
           + least(coalesce(qc.edit_events,0), 10) * 0.3
           - least(coalesce(qc.close_events,0), 5) * 3
           + case when qc.comments > 0 then greatest(coalesce(qc.avg_comment_len,0)/80.0, 0) else 0 end
           + case when qc.duplicate_links > 0 then -2 else 0 end
           + case when qtr.best_tag_rank is not null then 5.0 / (qtr.best_tag_rank) else 0 end
         ) as quality_score
  from question_core qc
  left join question_tag_rank qtr on qtr.question_id = qc.question_id
),
user_rollup as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.home_region,
         br.golds, br.silvers, br.bronzes,
         coalesce(avg(us.quality_score) filter (where us.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'), 0) as avg_q_quality_1y,
         coalesce(percentile_cont(0.9) within group (order by us.quality_score) filter (where us.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'), 0) as p90_q_quality_1y,
         coalesce(sum(case when us.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' then 1 else 0 end),0) as q_count_1y,
         coalesce(sum(us.answers) filter (where us.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'),0) as answers_placeholder,
         ua3.q_last3m,
         ua3.a_last3m,
         ua3.score_last3m
  from recent_users ru
  left join badge_recent br on br.userid = ru.user_id
  left join question_scored us on us.owner_user_id = ru.user_id
  left join lateral (
    select uaw.q_last3m, uaw.a_last3m, uaw.score_last3m
    from user_activity_win uaw
    where uaw.user_id = ru.user_id
    order by uaw.month desc nulls last
    limit 1
  ) ua3 on true
  group by ru.user_id, ru.displayname, ru.reputation, ru.home_region, br.golds, br.silvers, br.bronzes, ua3.q_last3m, ua3.a_last3m, ua3.score_last3m
),
user_ranked as (
  select ur.*,
         (
           ln(greatest(ur.reputation, 1)) / ln(10)
           + coalesce(ur.golds,0)*0.8 + coalesce(ur.silvers,0)*0.3 + coalesce(ur.bronzes,0)*0.1
           + coalesce(ur.avg_q_quality_1y,0)*0.7
           + coalesce(ur.p90_q_quality_1y,0)*0.5
           + coalesce(ur.q_count_1y,0)*0.2
           + coalesce(ur.q_last3m,0)*0.3
           + coalesce(ur.a_last3m,0)*0.25
           + coalesce(ur.score_last3m,0)*0.05
         ) as benchmark_score
  from user_rollup ur
),
candidate_questions as (
  select qs.question_id, qs.owner_user_id, qs.quality_score, qs.creationdate, qs.close_events, qs.views, qs.downvotes
  from question_scored qs
  where qs.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  union all
  select qs.question_id, qs.owner_user_id, qs.quality_score, qs.creationdate, qs.close_events, qs.views, qs.downvotes
  from question_scored qs
  where qs.close_events > 0
),
candidate_questions_dedup as (
  select cq.*,
         row_number() over (partition by cq.question_id order by cq.creationdate desc) as rn
  from candidate_questions cq
),
final as (
  select
    qr.question_id,
    coalesce(p.title, '(no title)') as title,
    p.tags,
    u.displayname as owner,
    ur.home_region,
    ur.reputation,
    ur.benchmark_score,
    qs.quality_score,
    qs.views,
    qs.answers,
    qs.upvotes,
    qs.downvotes,
    qs.comments,
    qs.close_events,
    qs.reopen_events,
    qs.duplicate_links,
    qs.related_links,
    case
      when qs.last_close_at is not null and qs.last_hist_at is not null
           and qs.last_close_at > qs.last_hist_at - interval '7 days'
      then 'recently_closed'
      when qs.close_events > 0 then 'historically_closed'
      else 'open_or_unknown'
    end as close_state,
    greatest(qs.creationdate, coalesce(qs.last_hist_at, qs.creationdate)) as last_activity_guess
  from candidate_questions_dedup qr
  join question_scored qs on qs.question_id = qr.question_id
  left join posts p on p.id = qs.question_id
  left join users u on u.id = qs.owner_user_id
  left join user_ranked ur on ur.user_id = qs.owner_user_id
  where qr.rn = 1
    and (
      (qs.quality_score >= 5 and coalesce(qs.views,0) >= 1000)
      or (qs.quality_score between -10 and 0 and coalesce(qs.downvotes,0) >= 3)
      or (qs.close_events > 0 and (qs.duplicate_links is null or qs.duplicate_links = 0))
    )
),
final_ranked as (
  select f.*,
         row_number() over (
           partition by coalesce(owner, 'anon'), date_trunc('month', last_activity_guess)
           order by benchmark_score desc nulls last, quality_score desc nulls last, question_id
         ) as rn_in_partition
  from final f
)
select *
from final_ranked
where rn_in_partition <= 5
order by benchmark_score desc nulls last, quality_score desc nulls last, question_id
limit 200;