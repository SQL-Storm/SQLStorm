-- {"query": "682.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2745}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.location,
         u.creationdate,
         coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
         date_trunc('month', u.creationdate) as signup_month,
         row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unspecified') order by u.reputation desc, u.id) as rn_loc
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_badge_agg as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
questions as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.creationdate as question_date,
         p.score as question_score,
         p.viewcount,
         p.answercount,
         p.tags,
         p.title,
         p.acceptedanswerid,
         p.closeddate,
         p.communityowneddate,
         case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate as answer_date,
         a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
q_activity as (
  select q.question_id,
         count(distinct a.answer_id) as answers_count,
         sum(case when a.answer_id = q.acceptedanswerid then 1 else 0 end) as has_accepted,
         avg(cast(a.answer_score as numeric)) as avg_answer_score,
         min(a.answer_date) as first_answer_date,
         max(a.answer_date) as last_answer_date
  from questions q
  left join answers a on a.question_id = q.question_id
  group by q.question_id
),
q_commenters as (
  select c.postid as question_id,
         count(case when c.score > 0 then 1 end) as pos_comments,
         count(case when c.score < 0 then 1 end) as neg_comments,
         count(distinct c.userid) as distinct_commenters
  from comments c
  join questions q on q.question_id = c.postid
  group by c.postid
),
q_votes as (
  select v.postid as question_id,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
         count(case when v.votetypeid = 2 then 1 end) as upvotes,
         count(case when v.votetypeid = 3 then 1 end) as downvotes,
         max(v.creationdate) as last_vote_date
  from votes v
  join questions q on q.question_id = v.postid
  group by v.postid
),
q_links as (
  select pl.postid as question_id,
         count(case when pl.linktypeid = 1 then 1 end) as linked_count,
         count(case when pl.linktypeid = 3 then 1 end) as duplicate_marks
  from postlinks pl
  join questions q on q.question_id = pl.postid
  group by pl.postid
),
q_close_reasons as (
  select ph.postid as question_id,
         max(case when ph.posthistorytypeid = 10 then ph.comment end) as raw_close_reason_id,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as close_vote_date
  from posthistory ph
  join questions q on q.question_id = ph.postid
  where ph.posthistorytypeid = 10
  group by ph.postid
),
close_reason_lu as (
  select cast(crt.id as varchar) as id_str, crt.name as close_reason_name
  from closereasontypes crt
),
q_enriched as (
  select q.*,
         qa.answers_count,
         qa.has_accepted,
         qa.avg_answer_score,
         qa.first_answer_date,
         qa.last_answer_date,
         qc.pos_comments,
         qc.neg_comments,
         qc.distinct_commenters,
         qv.net_votes,
         qv.upvotes,
         qv.downvotes,
         qv.last_vote_date,
         ql.linked_count,
         ql.duplicate_marks,
         cr.close_vote_date,
         cr.raw_close_reason_id,
         coalesce(crl.close_reason_name, 'Unknown') as close_reason_name
  from questions q
  left join q_activity qa on qa.question_id = q.question_id
  left join q_commenters qc on qc.question_id = q.question_id
  left join q_votes qv on qv.question_id = q.question_id
  left join q_links ql on ql.question_id = q.question_id
  left join q_close_reasons cr on cr.question_id = q.question_id
  left join close_reason_lu crl on crl.id_str = cr.raw_close_reason_id
),
tag_expanded as (
  select q.question_id,
         unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
  from q_enriched q
),
tag_agg as (
  select te.question_id,
         array_agg(te.tag order by te.tag) as tags_array,
         min(te.tag) as first_tag,
         max(te.tag) as last_tag,
         count(*) as tag_count
  from tag_expanded te
  group by te.question_id
),
user_post_stats as (
  select u.id as user_id,
         count(case when p.posttypeid = 1 then 1 end) as q_count,
         count(case when p.posttypeid = 2 then 1 end) as a_count,
         avg(case when p.posttypeid = 1 then nullif(p.score,0) end) as avg_q_score_nonzero,
         avg(case when p.posttypeid = 2 then nullif(p.score,0) end) as avg_a_score_nonzero,
         max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
questioner as (
  select q.question_id,
         q.asker_id,
         u.displayname as asker_name,
         u.reputation as asker_rep,
         u.location as asker_location,
         ups.q_count,
         ups.a_count,
         uba.total_badges,
         uba.gold_badges,
         uba.silver_badges,
         uba.bronze_badges,
         ru.rn_loc as asker_rank_in_location
  from q_enriched q
  left join recent_users ru on ru.user_id = q.asker_id
  left join users u on u.id = q.asker_id
  left join user_post_stats ups on ups.user_id = q.asker_id
  left join user_badge_agg uba on uba.userid = q.asker_id
),
answerer_mix as (
  select q.question_id,
         count(distinct a.answerer_id) as distinct_answerers,
         sum(case when ru.user_id is not null then 1 else 0 end) as recent_answerers,
         sum(case when u.reputation >= 10000 then 1 else 0 end) as highrep_answers
  from q_enriched q
  left join answers a on a.question_id = q.question_id
  left join users u on u.id = a.answerer_id
  left join recent_users ru on ru.user_id = a.answerer_id
  group by q.question_id
),
question_quality as (
  select q.question_id,
         case
           when coalesce(q.answers_count,0) = 0 and q.viewcount > 1000 then 'UnansweredPopular'
           when q.has_accepted = 1 and coalesce(q.net_votes,0) >= 5 then 'AcceptedWellVoted'
           when q.is_closed = 1 and coalesce(q.net_votes,0) < 0 then 'ClosedNegative'
           when coalesce(q.duplicate_marks,0) >= 1 then 'HasDuplicateMark'
           else 'Other'
         end as quality_bucket,
         greatest(
           coalesce(q.net_votes,0)
           + coalesce(q.upvotes,0)
           - coalesce(q.downvotes,0)
           + coalesce(q.answers_count,0) * 2
           + case when q.has_accepted = 1 then 5 else 0 end
           + least(coalesce(q.viewcount,0) / 100, 50),
           -50
         ) as quality_score
  from q_enriched q
),
monthly_rollup as (
  select date_trunc('month', q.question_date) as month,
         count(*) as questions,
         avg(coalesce(q.net_votes,0)) as avg_net_votes,
         percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) as p90_views,
         sum(case when q.is_closed = 1 then 1 else 0 end) as closed_questions
  from q_enriched q
  group by date_trunc('month', q.question_date)
),
ranked_questions as (
  select q.question_id,
         q.question_date,
         q.question_score,
         q.viewcount,
         qq.quality_score,
         qq.quality_bucket,
         row_number() over (partition by date_trunc('month', q.question_date) order by qq.quality_score desc, q.viewcount desc, q.question_id) as rn_month,
         dense_rank() over (order by qq.quality_score desc, q.viewcount desc) as global_rank
  from q_enriched q
  join question_quality qq on qq.question_id = q.question_id
),
dedup as (
  select q.question_id,
         q.title,
         q.tags,
         q.viewcount,
         q.net_votes,
         q.duplicate_marks,
         case when exists (
           select 1
           from postlinks pl
           where pl.linktypeid = 3
             and pl.relatedpostid = q.question_id
         ) then 1 else 0 end as is_target_of_duplicate
  from q_enriched q
),
final_set as (
  select
    q.question_id,
    q.title,
    coalesce(ta.tags_array, ARRAY[]::varchar[]) as tags_array,
    q.question_date,
    q.viewcount,
    q.upvotes,
    q.downvotes,
    q.net_votes,
    q.answers_count,
    q.has_accepted,
    q.is_closed,
    q.close_reason_name,
    ql.quality_bucket,
    ql.quality_score,
    am.distinct_answerers,
    am.recent_answerers,
    am.highrep_answers,
    qu.asker_name,
    qu.asker_rep,
    qu.asker_location,
    qu.asker_rank_in_location,
    qu.total_badges,
    qu.gold_badges,
    qu.silver_badges,
    qu.bronze_badges,
    rq.rn_month,
    rq.global_rank,
    mr.month,
    mr.p90_views,
    d.is_target_of_duplicate,
    q.duplicate_marks
  from q_enriched q
  left join tag_agg ta on ta.question_id = q.question_id
  left join answerer_mix am on am.question_id = q.question_id
  left join questioner qu on qu.question_id = q.question_id
  left join ranked_questions rq on rq.question_id = q.question_id
  left join monthly_rollup mr on mr.month = date_trunc('month', q.question_date)
  left join question_quality ql on ql.question_id = q.question_id
  left join dedup d on d.question_id = q.question_id
)
select *
from (
  select * from final_set
  where coalesce(quality_score, -9999) > 0
  union all
  select * from final_set
  where is_closed = 1 and coalesce(duplicate_marks,0) >= 1
) u
where coalesce(array_length(tags_array,1),0) between 1 and 5
  and (coalesce(net_votes,0) + coalesce(answers_count,0)) > 0
  and (is_target_of_duplicate is null or is_target_of_duplicate = 0)
order by global_rank nulls last, rn_month nulls last, question_date desc
limit 500;