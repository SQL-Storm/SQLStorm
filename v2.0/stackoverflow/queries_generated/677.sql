-- {"query": "677.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3331} 
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(lower(u.websiteurl)), ''), 'n/a') as norm_website,
         date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= now() - interval '5 years'
),
q_posts as (
  select p.id as post_id,
         p.owneruserid as user_id,
         p.score,
         p.viewcount,
         p.creationdate,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.closeddate,
         p.communityowneddate,
         p.answercount
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.id as answer_id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.score as answer_score,
         p.creationdate as answer_created
  from posts p
  where p.posttypeid = 2
),
tag_explode as (
  select q.post_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from q_posts q
  where q.tags is not null and length(q.tags) > 2
),
user_activity as (
  select ru.user_id,
         count(distinct q.post_id) as questions_count,
         count(distinct a.answer_id) as answers_count,
         sum(greatest(q.score,0)) as q_upscore,
         sum(greatest(a.answer_score,0)) as a_upscore,
         sum(case when q.closeddate is not null then 1 else 0 end) as closed_q_count,
         sum(coalesce(q.viewcount,0)) as total_q_views,
         min(q.creationdate) as first_q_date,
         max(q.creationdate) as last_q_date
  from recent_users ru
  left join q_posts q on q.user_id = ru.user_id
  left join a_posts a on a.user_id = ru.user_id
  group by ru.user_id
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then v.bountyamount else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then v.bountyamount else 0 end) as bounty_awarded
  from votes v
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comment_count,
         sum(greatest(c.score,0)) as comment_upscore,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
ph_close_reasons as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
         count(*) filter (where ph.posthistorytypeid in (12,10)) as mod_actions,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
         max(case
               when ph.posthistorytypeid = 10 then
                 nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
               else null
             end)::int as last_close_reason_raw
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select pl.postid,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
tag_metrics as (
  select te.tag,
         count(distinct te.post_id) as tagged_questions,
         avg(q.score)::numeric(12,4) as avg_tag_q_score,
         percentile_cont(0.5) within group (order by coalesce(q.viewcount,0)) as p50_views,
         count(*) filter (where q.acceptedanswerid is not null) as with_accepted
  from tag_explode te
  join q_posts q on q.post_id = te.post_id
  group by te.tag
),
user_badges as (
  select b.userid as user_id,
         count(*) as badge_count,
         count(*) filter (where b.class = 1) as gold_count,
         count(*) filter (where b.class = 2) as silver_count,
         count(*) filter (where b.class = 3) as bronze_count,
         count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
question_rollups as (
  select q.post_id,
         q.user_id,
         q.score,
         q.viewcount,
         q.title,
         q.creationdate,
         q.closeddate,
         q.acceptedanswerid,
         coalesce(va.upvotes,0) as upvotes,
         coalesce(va.downvotes,0) as downvotes,
         coalesce(va.favorites,0) as favorites,
         coalesce(va.bounty_started,0) as bounty_started,
         coalesce(va.bounty_awarded,0) as bounty_awarded,
         coalesce(ca.comment_count,0) as comment_count,
         coalesce(ca.comment_upscore,0) as comment_upscore,
         ca.last_comment_date,
         coalesce(ph.close_events,0) as close_events,
         coalesce(ph.reopen_events,0) as reopen_events,
         ph.last_closed_date,
         ph.last_close_reason_raw,
         coalesce(dl.duplicate_links,0) as duplicate_links,
         coalesce(dl.related_links,0) as related_links
  from q_posts q
  left join vote_agg va on va.postid = q.post_id
  left join comment_agg ca on ca.postid = q.post_id
  left join ph_close_reasons ph on ph.postid = q.post_id
  left join dup_links dl on dl.postid = q.post_id
),
answer_latency as (
  select q.post_id,
         min(a.answer_created) as first_answer_date,
         count(a.answer_id) as answer_count,
         avg(a.answer_score)::numeric(12,4) as avg_answer_score
  from q_posts q
  left join a_posts a on a.question_id = q.post_id
  group by q.post_id
),
user_question_window as (
  select qr.user_id,
         qr.post_id,
         qr.creationdate,
         row_number() over (partition by qr.user_id order by qr.creationdate) as rn,
         lag(qr.creationdate) over (partition by qr.user_id order by qr.creationdate) as prev_q_date,
         lead(qr.creationdate) over (partition by qr.user_id order by qr.creationdate) as next_q_date,
         sum(qr.score) over (partition by qr.user_id order by qr.creationdate rows between unbounded preceding and current row) as running_q_score
  from question_rollups qr
),
topk_user_tags as (
  select te.tag,
         q.user_id,
         count(*) as cnt,
         dense_rank() over (partition by q.user_id order by count(*) desc, te.tag asc) as rnk
  from tag_explode te
  join q_posts q on q.post_id = te.post_id
  group by te.tag, q.user_id
),
cohort_stats as (
  select ru.cohort_month,
         count(*) as users_in_cohort,
         avg(ru.reputation)::numeric(12,2) as avg_rep,
         percentile_cont(0.9) within group (order by ru.reputation) as p90_rep
  from recent_users ru
  group by ru.cohort_month
),
accepted_effect as (
  select q.post_id,
         case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
         case when q.acceptedanswerid is not null then q.score else null end as score_when_accepted
  from q_posts q
),
final_users as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.cohort_month,
         ru.norm_website,
         ua.questions_count,
         ua.answers_count,
         coalesce(ub.badge_count,0) as badge_count,
         coalesce(ub.gold_count,0) as gold_count,
         coalesce(ub.silver_count,0) as silver_count,
         coalesce(ub.bronze_count,0) as bronze_count,
         coalesce(ub.tag_badges,0) as tag_badges,
         ua.total_q_views,
         ua.closed_q_count,
         ua.first_q_date,
         ua.last_q_date
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
),
ranked_questions as (
  select qr.*,
         al.first_answer_date,
         al.answer_count,
         al.avg_answer_score,
         ae.has_accepted,
         ae.score_when_accepted,
         date_part('epoch', al.first_answer_date - qr.creationdate) / 60.0 as mins_to_first_answer,
         case
           when qr.closeddate is not null then 'closed'
           when qr.acceptedanswerid is not null then 'answered'
           when coalesce(al.answer_count,0) = 0 then 'no_answers'
           else 'open'
         end as q_status,
         row_number() over (partition by qr.user_id order by qr.score desc nulls last, qr.viewcount desc nulls last, qr.post_id) as rank_in_user
  from question_rollups qr
  left join answer_latency al on al.post_id = qr.post_id
  left join accepted_effect ae on ae.post_id = qr.post_id
),
heavy_set_ops as (
  select user_id, 'top_scorers' as bucket
  from ranked_questions
  where score >= (select percentile_cont(0.95) within group (order by coalesce(score,0)) from ranked_questions)
  union all
  select user_id, 'frequent_askers' as bucket
  from user_activity
  where questions_count >= (select max(questions_count) from user_activity) - 1
  union
  select user_id, 'no_answers_yet' as bucket
  from ranked_questions
  where coalesce(answer_count,0) = 0 and creationdate >= now() - interval '1 year'
),
complex_predicate as (
  select rq.post_id
  from ranked_questions rq
  where (
          coalesce(rq.upvotes - rq.downvotes, 0) > 10
          and coalesce(rq.comment_count,0) >= 2
          and (rq.duplicate_links = 0 or rq.duplicate_links is null)
        )
        or (
          rq.has_accepted = 1
          and coalesce(rq.mins_to_first_answer, 1e9) < 60
          and (rq.score + coalesce(rq.favorites,0)) >= 5
        )
        or (
          rq.closeddate is not null
          and rq.downvotes > rq.upvotes
          and rq.viewcount > 1000
        )
),
user_top_tag as (
  select tut.user_id,
         min(case when tut.rnk = 1 then tut.tag end) as top_tag
  from topk_user_tags tut
  where tut.rnk = 1
  group by tut.user_id
),
null_logic_examples as (
  select rq.post_id,
         coalesce(nullif(btrim(rq.title), ''), '(untitled)') as safe_title,
         nullif(rq.last_comment_date, rq.creationdate) as last_commented_if_diff,
         case when rq.bounty_awarded is null and rq.bounty_started > 0 then 1 else 0 end as bounty_open_flag
  from ranked_questions rq
)
select
  fu.user_id,
  fu.displayname,
  fu.reputation,
  fu.cohort_month,
  fu.norm_website,
  utl.top_tag,
  fu.questions_count,
  fu.answers_count,
  fu.badge_count,
  fu.gold_count,
  fu.silver_count,
  fu.bronze_count,
  fu.tag_badges,
  fu.total_q_views,
  fu.closed_q_count,
  count(distinct rq.post_id) as total_qs_considered,
  sum(case when rq.q_status = 'closed' then 1 else 0 end) as qs_closed,
  sum(case when rq.has_accepted = 1 then 1 else 0 end) as qs_with_accepted,
  avg(rq.score)::numeric(12,3) as avg_q_score,
  avg(coalesce(rq.viewcount,0))::numeric(12,3) as avg_q_views,
  avg(coalesce(rq.mins_to_first_answer, 0))::numeric(12,2) as avg_mins_to_first_answer,
  percentile_cont(0.5) within group (order by coalesce(rq.mins_to_first_answer, 0)) as p50_answer_mins,
  sum(case when cp.post_id is not null then 1 else 0 end) as complex_hits,
  count(distinct case when hs.bucket = 'top_scorers' then fu.user_id end) as top_scorer_flag,
  count(distinct case when hs.bucket = 'frequent_askers' then fu.user_id end) as frequent_asker_flag,
  count(distinct case when hs.bucket = 'no_answers_yet' then fu.user_id end) as no_answers_recent_flag,
  max(le.last_commented_if_diff) as last_commented_if_diff_any,
  sum(le.bounty_open_flag) as bounty_open_questions,
  string_agg(distinct case when rq.rank_in_user <= 3 then te.tag end, ',' order by te.tag) as top3_q_tags_union,
  string_agg(distinct case when rq.rank_in_user <= 3 then le.safe_title end, ' | ' order by rq.score desc nulls last) as top3_q_titles
from final_users fu
left join ranked_questions rq on rq.user_id = fu.user_id
left join complex_predicate cp on cp.post_id = rq.post_id
left join heavy_set_ops hs on hs.user_id = fu.user_id
left join null_logic_examples le on le.post_id = rq.post_id
left join tag_explode te on te.post_id = rq.post_id
left join user_top_tag utl on utl.user_id = fu.user_id
group by
  fu.user_id, fu.displayname, fu.reputation, fu.cohort_month, fu.norm_website,
  utl.top_tag,
  fu.questions_count, fu.answers_count, fu.badge_count, fu.gold_count, fu.silver_count, fu.bronze_count, fu.tag_badges, fu.total_q_views, fu.closed_q_count
having count(distinct rq.post_id) >= 5
qualify row_number() over (order by qs_with_accepted desc, avg_q_score desc, total_qs_considered desc, fu.reputation desc, fu.user_id) <= 200;