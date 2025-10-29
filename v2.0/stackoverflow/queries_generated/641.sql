-- {"query": "641.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2763} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         date_trunc('month', u.creationdate) as cohort_month,
         coalesce(nullif(badge_counts.total_badges, 0), 0) as total_badges
  from users u
  left join (
    select userId, count(*) as total_badges
    from badges
    where date >= now() - interval '5 years'
    group by userId
  ) badge_counts on badge_counts.userid = u.id
  where u.creationdate >= now() - interval '5 years'
),
question_activity as (
  select p.owneruserid as user_id,
         date_trunc('month', p.creationdate) as month_bucket,
         count(*) filter (where p.posttypeid = 1) as questions,
         sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
         sum(coalesce(p.score,0)) filter (where p.posttypeid = 1) as question_score,
         count(distinct p.id) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_questions
  from posts p
  where p.owneruserid is not null
    and p.creationdate >= now() - interval '5 years'
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
answer_activity as (
  select p.owneruserid as user_id,
         date_trunc('month', p.creationdate) as month_bucket,
         count(*) filter (where p.posttypeid = 2) as answers,
         sum(coalesce(p.score,0)) filter (where p.posttypeid = 2) as answer_score
  from posts p
  where p.owneruserid is not null
    and p.creationdate >= now() - interval '5 years'
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
comment_activity as (
  select c.userid as user_id,
         date_trunc('month', c.creationdate) as month_bucket,
         count(*) as comments,
         sum(coalesce(c.score,0)) as comment_score
  from comments c
  where c.userid is not null
    and c.creationdate >= now() - interval '5 years'
  group by c.userid, date_trunc('month', c.creationdate)
),
vote_activity as (
  select v.userid as user_id,
         date_trunc('month', v.creationdate) as month_bucket,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) filter (where v.votetypeid = 5) as favorites_cast,
         count(*) filter (where v.votetypeid in (8,9)) as bounties_touch
  from votes v
  where v.userid is not null
    and v.creationdate >= now() - interval '5 years'
  group by v.userid, date_trunc('month', v.creationdate)
),
edits_and_closures as (
  select ph.userid as user_id,
         date_trunc('month', ph.creationdate) as month_bucket,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits,
         count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_votes
  from posthistory ph
  where ph.userid is not null
    and ph.creationdate >= now() - interval '5 years'
  group by ph.userid, date_trunc('month', ph.creationdate)
),
links_and_duplicates as (
  select p.owneruserid as user_id,
         date_trunc('month', pl.creationdate) as month_bucket,
         count(*) filter (where pl.linktypeid = 1) as links_created,
         count(*) filter (where pl.linktypeid = 3) as dup_links
  from postlinks pl
  join posts p on p.id = pl.postid
  where p.owneruserid is not null
    and pl.creationdate >= now() - interval '5 years'
  group by p.owneruserid, date_trunc('month', pl.creationdate)
),
monthly_user_activity as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.cohort_month,
         coalesce(qa.month_bucket, aa.month_bucket, ca.month_bucket, va.month_bucket, ea.month_bucket, ld.month_bucket) as month_bucket,
         coalesce(qa.questions, 0) as questions,
         coalesce(qa.question_views, 0) as question_views,
         coalesce(qa.question_score, 0) as question_score,
         coalesce(qa.accepted_questions, 0) as accepted_questions,
         coalesce(aa.answers, 0) as answers,
         coalesce(aa.answer_score, 0) as answer_score,
         coalesce(ca.comments, 0) as comments,
         coalesce(ca.comment_score, 0) as comment_score,
         coalesce(va.upvotes_cast, 0) as upvotes_cast,
         coalesce(va.downvotes_cast, 0) as downvotes_cast,
         coalesce(va.favorites_cast, 0) as favorites_cast,
         coalesce(va.bounties_touch, 0) as bounties_touch,
         coalesce(ea.edits, 0) as edits,
         coalesce(ea.close_reopen_votes, 0) as close_reopen_votes,
         coalesce(ld.links_created, 0) as links_created,
         coalesce(ld.dup_links, 0) as dup_links,
         ru.total_badges
  from recent_users ru
  left join question_activity qa on qa.user_id = ru.user_id
  full outer join answer_activity aa on aa.user_id = ru.user_id and aa.month_bucket = qa.month_bucket
  full outer join comment_activity ca on ca.user_id = ru.user_id and ca.month_bucket = coalesce(qa.month_bucket, aa.month_bucket)
  full outer join vote_activity va on va.user_id = ru.user_id and va.month_bucket = coalesce(qa.month_bucket, aa.month_bucket, ca.month_bucket)
  full outer join edits_and_closures ea on ea.user_id = ru.user_id and ea.month_bucket = coalesce(qa.month_bucket, aa.month_bucket, ca.month_bucket, va.month_bucket)
  full outer join links_and_duplicates ld on ld.user_id = ru.user_id and ld.month_bucket = coalesce(qa.month_bucket, aa.month_bucket, ca.month_bucket, va.month_bucket, ea.month_bucket)
),
augmented as (
  select mua.*,
         case
           when mua.answers = 0 and mua.questions = 0 and mua.comments = 0 and mua.edits = 0 then 1
           else 0
         end as is_inactive_month,
         case
           when mua.answers > 0 then mua.answer_score::numeric / nullif(mua.answers, 0)
           else null
         end as avg_answer_score,
         case
           when mua.questions > 0 then mua.question_views::numeric / nullif(mua.questions, 0)
           else null
         end as avg_question_views,
         case
           when mua.questions > 0 then mua.accepted_questions::numeric / nullif(mua.questions, 0)
           else null
         end as question_accept_rate,
         (coalesce(mua.upvotes_cast,0) - coalesce(mua.downvotes_cast,0)) as net_votes_cast,
         coalesce(mua.answers,0) + coalesce(mua.questions,0) + coalesce(mua.comments,0) + coalesce(mua.edits,0) as total_contributions
  from monthly_user_activity mua
),
ranked as (
  select a.*,
         row_number() over (partition by a.user_id order by a.month_bucket) as month_seq,
         sum(a.total_contributions) over (partition by a.user_id order by a.month_bucket rows between unbounded preceding and current row) as running_contribs,
         avg(coalesce(a.answer_score,0)) over (partition by a.user_id order by a.month_bucket rows between 2 preceding and current row) as rolling_answer_score_avg3,
         lag(a.total_contributions) over (partition by a.user_id order by a.month_bucket) as prev_total_contribs
  from augmented a
),
dense_cohorts as (
  select r.*,
         dense_rank() over (order by r.cohort_month) as cohort_rank,
         dense_rank() over (partition by r.user_id order by r.month_bucket) as month_rank_within_user
  from ranked r
),
tag_influence as (
  select p.owneruserid as user_id,
         date_trunc('month', p.creationdate) as month_bucket,
         count(*) as tagged_questions,
         sum(case when position('python' in coalesce(p.tags,'')) > 0 then 1 else 0 end) as python_qs,
         sum(case when position('java' in coalesce(p.tags,'')) > 0 then 1 else 0 end) as java_qs
  from posts p
  where p.posttypeid = 1
    and p.owneruserid is not null
    and p.creationdate >= now() - interval '5 years'
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
quality_flags as (
  select p.owneruserid as user_id,
         date_trunc('month', p.creationdate) as month_bucket,
         count(*) filter (where p.score >= 5) as high_score_posts,
         count(*) filter (where p.score < 0) as negative_posts,
         count(*) filter (where p.closeddate is not null) as closed_posts
  from posts p
  where p.owneruserid is not null
    and p.creationdate >= now() - interval '5 years'
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
user_levels as (
  select u.id as user_id,
         case
           when u.reputation >= 20000 then 'legend'
           when u.reputation >= 10000 then 'expert'
           when u.reputation >= 3000 then 'advanced'
           when u.reputation >= 1000 then 'intermediate'
           else 'beginner'
         end as level
  from users u
)
select d.user_id,
       d.displayname,
       ul.level,
       d.cohort_month,
       d.month_bucket,
       d.month_seq,
       d.questions,
       d.answers,
       d.comments,
       d.edits,
       d.links_created,
       d.dup_links,
       d.question_views,
       d.question_score,
       d.answer_score,
       d.avg_answer_score,
       d.avg_question_views,
       d.question_accept_rate,
       d.upvotes_cast,
       d.downvotes_cast,
       d.net_votes_cast,
       d.favorites_cast,
       d.bounties_touch,
       d.close_reopen_votes,
       d.total_contributions,
       d.running_contribs,
       d.rolling_answer_score_avg3,
       d.prev_total_contribs,
       coalesce(ti.tagged_questions,0) as tagged_questions,
       coalesce(ti.python_qs,0) as python_qs,
       coalesce(ti.java_qs,0) as java_qs,
       coalesce(qf.high_score_posts,0) as high_score_posts,
       coalesce(qf.negative_posts,0) as negative_posts,
       coalesce(qf.closed_posts,0) as closed_posts,
       d.total_badges,
       case when d.is_inactive_month = 1 then 'inactive' else 'active' end as activity_flag,
       case
         when coalesce(qf.closed_posts,0) > 0 and coalesce(qf.negative_posts,0) > 2 then 'risky'
         when coalesce(qf.high_score_posts,0) >= 3 then 'high_quality'
         when coalesce(d.total_contributions,0) >= 10 then 'prolific'
         else 'normal'
       end as month_classification
from dense_cohorts d
left join tag_influence ti on ti.user_id = d.user_id and ti.month_bucket = d.month_bucket
left join quality_flags qf on qf.user_id = d.user_id and qf.month_bucket = d.month_bucket
left join user_levels ul on ul.user_id = d.user_id
where d.month_bucket is not null
  and (
    d.total_contributions > 0
    or d.month_seq in (1, 12, 24, 36, 48, 60)
  )
  and (
    coalesce(d.avg_answer_score,0) >= 0
    or d.answers = 0
  )
order by d.reputation desc, d.user_id, d.month_bucket;