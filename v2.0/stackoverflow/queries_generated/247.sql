-- {"query": "247.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3008} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         u.upvotes,
         u.downvotes,
         date_trunc('month', u.creationdate) as cohort_month,
         row_number() over (order by u.reputation desc, u.id) as rn_global
  from users u
  where u.creationdate >= now() - interval '5 years'
),
top_cohorts as (
  select cohort_month,
         count(*) as users_in_cohort,
         avg(reputation) as avg_rep_cohort,
         percentile_disc(0.9) within group (order by reputation) as p90_rep,
         max(reputation) as max_rep
  from recent_users
  group by cohort_month
),
q_posts as (
  select p.id as post_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.title,
         p.tags,
         p.closeddate,
         p.acceptedanswerid,
         p.commentcount
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.id as answer_id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
first_answer_per_question as (
  select a.question_id,
         min(a.creationdate) as first_answer_time
  from a_posts a
  group by a.question_id
),
question_activity as (
  select q.post_id,
         q.user_id,
         q.creationdate,
         q.score,
         q.viewcount,
         q.answercount,
         q.title,
         q.tags,
         q.closeddate,
         q.acceptedanswerid,
         q.commentcount,
         fa.first_answer_time,
         extract(epoch from (fa.first_answer_time - q.creationdate)) as secs_to_first_answer
  from q_posts q
  left join first_answer_per_question fa on fa.question_id = q.post_id
),
user_question_stats as (
  select qa.user_id,
         count(*) filter (where qa.closeddate is null) as open_questions,
         count(*) filter (where qa.closeddate is not null) as closed_questions,
         avg(nullif(qa.score, 0)) as avg_nonzero_qscore,
         avg(qa.viewcount) as avg_views,
         percentile_cont(0.5) within group (order by qa.secs_to_first_answer) as median_secs_first_answer,
         max(qa.viewcount) as max_views,
         sum(qa.commentcount) as total_q_comments
  from question_activity qa
  group by qa.user_id
),
user_answer_stats as (
  select a.user_id,
         count(*) as answers,
         avg(a.score) as avg_ascore,
         sum(case when a.score >= 0 then 1 else 0 end) as nonneg_answers,
         sum(case when a.score < 0 then 1 else 0 end) as neg_answers,
         max(a.score) as best_ascore
  from a_posts a
  group by a.user_id
),
user_votes as (
  select v.userid as user_id,
         count(*) filter (where v.votetypeid = 2) as upmods_cast,
         count(*) filter (where v.votetypeid = 3) as downmods_cast,
         count(*) filter (where v.votetypeid = 5) as favorites_cast,
         count(*) filter (where v.votetypeid = 8) as bounties_started,
         coalesce(sum(case when v.votetypeid in (8,9) then v.bountyamount end),0) as bounty_total_given
  from votes v
  where v.userid is not null
  group by v.userid
),
post_votes as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcv,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcv,
         count(*) filter (where v.votetypeid = 5) as favorites_rcv
  from votes v
  group by v.postid
),
question_with_votes as (
  select qa.*,
         pv.upvotes_rcv,
         pv.downvotes_rcv,
         pv.favorites_rcv
  from question_activity qa
  left join post_votes pv on pv.postid = qa.post_id
),
tag_split as (
  select qw.post_id,
         unnest(string_to_array(substring(qw.tags, 2, greatest(length(qw.tags)-2,0)), '><')) as tag
  from question_with_votes qw
  where qw.tags is not null
),
top_user_tags as (
  select qw.user_id,
         t.tag,
         count(*) as tag_q_count,
         row_number() over (partition by qw.user_id order by count(*) desc, min(qw.creationdate)) as rn_tag
  from question_with_votes qw
  join tag_split t on t.post_id = qw.post_id
  group by qw.user_id, t.tag
),
badges_agg as (
  select b.userid as user_id,
         count(*) as total_badges,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
last_comment_per_post as (
  select c.postid,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
user_last_comment_activity as (
  select p.owneruserid as user_id,
         max(lc.last_comment_date) as last_comment_on_own_post
  from last_comment_per_post lc
  join posts p on p.id = lc.postid
  where p.owneruserid is not null
  group by p.owneruserid
),
closure_details as (
  select ph.postid,
         min(ph.creationdate) as first_close_date,
         max(ph.creationdate) as last_close_date,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
         sum(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then 1 else 0 end) as close_reasons_with_code
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
questions_enriched as (
  select qw.*,
         cd.first_close_date,
         cd.last_close_date,
         cd.close_events,
         cd.reopen_events
  from question_with_votes qw
  left join closure_details cd on cd.postid = qw.post_id
),
user_engagement as (
  select qu.user_id,
         count(*) as questions_total,
         sum(case when qu.acceptedanswerid is not null then 1 else 0 end) as questions_with_accept,
         avg(case when qu.acceptedanswerid is not null then 1.0 else 0.0 end) as acceptance_rate,
         avg(coalesce(qu.upvotes_rcv,0) - coalesce(qu.downvotes_rcv,0)) as avg_net_votes_rcv,
         avg(coalesce(qu.favorites_rcv,0)) as avg_favorites_rcv,
         avg(case when qu.first_answer_time is not null then 1.0 else 0.0 end) as answered_ratio
  from questions_enriched qu
  group by qu.user_id
),
user_ranked as (
  select ru.*,
         coalesce(uqs.open_questions,0) as open_questions,
         coalesce(uqs.closed_questions,0) as closed_questions,
         uqs.avg_nonzero_qscore,
         uqs.avg_views,
         uqs.median_secs_first_answer,
         uqs.max_views,
         uqs.total_q_comments,
         coalesce(uas.answers,0) as answers,
         uas.avg_ascore,
         uas.nonneg_answers,
         uas.neg_answers,
         uas.best_ascore,
         coalesce(uv.upmods_cast,0) as upmods_cast,
         coalesce(uv.downmods_cast,0) as downmods_cast,
         coalesce(uv.favorites_cast,0) as favorites_cast,
         coalesce(uv.bounties_started,0) as bounties_started,
         coalesce(uv.bounty_total_given,0) as bounty_total_given,
         coalesce(ba.total_badges,0) as total_badges,
         coalesce(ba.gold_badges,0) as gold_badges,
         coalesce(ba.silver_badges,0) as silver_badges,
         coalesce(ba.bronze_badges,0) as bronze_badges,
         coalesce(ba.tag_badges,0) as tag_badges,
         ue.questions_total,
         ue.questions_with_accept,
         ue.acceptance_rate,
         ue.avg_net_votes_rcv,
         ue.avg_favorites_rcv,
         ue.answered_ratio,
         ulc.last_comment_on_own_post,
         tct.users_in_cohort,
         tct.avg_rep_cohort,
         tct.p90_rep,
         tct.max_rep
  from recent_users ru
  left join user_question_stats uqs on uqs.user_id = ru.user_id
  left join user_answer_stats uas on uas.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  left join badges_agg ba on ba.user_id = ru.user_id
  left join user_engagement ue on ue.user_id = ru.user_id
  left join user_last_comment_activity ulc on ulc.user_id = ru.user_id
  left join top_cohorts tct on tct.cohort_month = ru.cohort_month
),
top_tag_choice as (
  select tut.user_id,
         max(case when tut.rn_tag = 1 then tut.tag end) as top_tag,
         max(case when tut.rn_tag = 2 then tut.tag end) as second_tag
  from top_user_tags tut
  where tut.rn_tag <= 2
  group by tut.user_id
),
score_windows as (
  select ur.*,
         avg(coalesce(answers,0) + coalesce(open_questions,0)) over (partition by date_trunc('year', creationdate)) as avg_yearly_prod,
         rank() over (order by coalesce(ur.acceptance_rate,0) desc, coalesce(ur.avg_net_votes_rcv,0) desc, ur.reputation desc) as r_accept_net_rep,
         dense_rank() over (order by coalesce(ur.avg_views,0) desc) as r_views
  from user_ranked ur
),
final_rank as (
  select sw.*,
         coalesce(0.4 * coalesce(acceptance_rate,0)
                + 0.2 * (coalesce(avg_net_votes_rcv,0) / nullif(answers + questions_total,0))
                + 0.2 * (coalesce(avg_ascore,0) / nullif(best_ascore,1))
                + 0.1 * least(log(1 + coalesce(total_badges,0)), 5)
                + 0.1 * (coalesce(upmods_cast,0) - coalesce(downmods_cast,0)) / nullif(upmods_cast + downmods_cast,0)
           , 0) as engagement_score,
         case
           when location ilike '%remote%' then 'Remote-leaning'
           when location ilike '%usa%' or location ilike '%united states%' then 'US'
           when location is null or btrim(location) = '' then 'Unknown'
           else 'Other'
         end as loc_bucket,
         coalesce(top_tag, 'unknown') as primary_tag,
         coalesce(second_tag, 'unknown') as secondary_tag
  from score_windows sw
  left join top_tag_choice ttc on ttc.user_id = sw.user_id
),
ranked as (
  select fr.*,
         ntile(10) over (order by engagement_score desc nulls last) as decile,
         row_number() over (partition by loc_bucket order by engagement_score desc nulls last, reputation desc) as rn_loc
  from final_rank fr
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.cohort_month,
  r.loc_bucket,
  r.primary_tag,
  r.secondary_tag,
  r.engagement_score,
  r.decile,
  r.r_accept_net_rep,
  r.r_views,
  r.avg_yearly_prod,
  r.questions_total,
  r.answers,
  r.acceptance_rate,
  r.avg_net_votes_rcv,
  r.avg_favorites_rcv,
  r.avg_ascore,
  r.best_ascore,
  r.open_questions,
  r.closed_questions,
  r.median_secs_first_answer,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.tag_badges,
  r.upmods_cast,
  r.downmods_cast,
  r.bounties_started,
  r.bounty_total_given,
  r.last_comment_on_own_post,
  r.users_in_cohort,
  r.avg_rep_cohort,
  r.p90_rep,
  r.max_rep
from ranked r
where r.decile in (1,2,3,4,5,6,7,8,9,10)
  and (r.primary_tag is distinct from r.secondary_tag or r.secondary_tag is null)
  and (r.acceptance_rate is not null or r.answers > 0 or r.questions_total > 0)
order by r.decile, r.engagement_score desc nulls last, r.reputation desc, r.user_id
limit 500;