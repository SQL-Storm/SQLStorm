-- {"query": "212.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2964} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '6 months' from posts p)
),
active_questions as (
    select p.id as question_id,
           p.owneruserid as asker_id,
           p.creationdate as question_created,
           p.score as question_score,
           p.viewcount,
           p.title,
           string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_list,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(pp.creationdate)) - interval '12 months' from posts pp)
),
answers as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid as answerer_id,
           a.creationdate as answer_created,
           a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
q_activity as (
    select q.question_id,
           count(distinct a.answer_id) as answer_count,
           max(a.answer_score) as max_answer_score,
           min(a.answer_score) filter (where a.answer_score is not null) as min_answer_score,
           sum(case when a.answer_score > 0 then 1 else 0 end) as pos_answer_cnt,
           sum(case when a.answer_score < 0 then 1 else 0 end) as neg_answer_cnt,
           count(distinct c.id) as comment_count
    from active_questions q
    left join answers a on a.question_id = q.question_id
    left join comments c on c.postid = q.question_id
    group by q.question_id
),
tag_expansion as (
    select q.question_id,
           lower(trim(t)) as tag
    from active_questions q
         cross join lateral unnest(q.tag_list) as t
),
top_tags as (
    select tag,
           count(*) as tag_q_count,
           sum(coalesce(q.viewcount,0)) as tag_views,
           avg(coalesce(q.questionscore,0)) as avg_q_score
    from (
        select te.tag, q.title, q.viewcount, q.question_score as questionscore
        from tag_expansion te
        join active_questions q on q.question_id = te.question_id
    ) s
    group by tag
),
badge_summary as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_cnt,
           sum(case when b.class = 2 then 1 else 0 end) as silver_cnt,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_cnt,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '12 months' from posts p)
    group by v.postid
),
dup_links as (
    select pl.postid as duplicate_id,
           pl.relatedpostid as canonical_id,
           count(*) as link_cnt
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
close_events as (
    select ph.postid,
           max(ph.creationdate) as last_closed_at,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
close_reason_names as (
    select crt.id as reason_id, crt.name as reason_name
    from closereasontypes crt
),
q_enriched as (
    select q.question_id,
           q.asker_id,
           q.title,
           q.question_created,
           q.question_score,
           q.viewcount,
           q.acceptedanswerid,
           qa.answer_count,
           qa.pos_answer_cnt,
           qa.neg_answer_cnt,
           coalesce(va.upvotes,0) as upvotes,
           coalesce(va.downvotes,0) as downvotes,
           coalesce(va.favorites,0) as favorites,
           coalesce(va.bounty_total,0) as bounty_total,
           cl.last_closed_at,
           crn.reason_name as last_close_reason,
           case
             when q.acceptedanswerid is not null then 'accepted'
             when qa.answer_count > 0 then 'answered'
             when cl.last_closed_at is not null then 'closed'
             else 'open'
           end as q_status
    from active_questions q
    left join q_activity qa on qa.question_id = q.question_id
    left join vote_agg va on va.postid = q.question_id
    left join close_events cl on cl.postid = q.question_id
    left join close_reason_names crn on crn.reason_id = cl.last_close_reason_id
),
user_stats as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           coalesce(bs.gold_cnt,0) as gold_cnt,
           coalesce(bs.silver_cnt,0) as silver_cnt,
           coalesce(bs.bronze_cnt,0) as bronze_cnt,
           coalesce(bs.tag_badges,0) as tag_badges,
           sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
           sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
           sum(coalesce(p.score,0)) as total_post_score
    from users u
    left join badges bs on bs.userid = u.id
    left join posts p on p.owneruserid = u.id
    group by u.id, u.displayname, u.reputation, bs.gold_cnt, bs.silver_cnt, bs.bronze_cnt, bs.tag_badges
),
user_recent_activity as (
    select u.id as user_id,
           max(p.creationdate) filter (where p.posttypeid = 1) as last_q_date,
           max(p.creationdate) filter (where p.posttypeid = 2) as last_a_date,
           count(*) filter (where p.creationdate >= now() - interval '30 days') as posts_30d
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
tag_rank as (
    select tag,
           tag_q_count,
           tag_views,
           avg_q_score,
           dense_rank() over (order by tag_q_count desc, tag_views desc, tag asc) as popularity_rank
    from top_tags
),
paired_counts as (
    select q.question_id,
           count(distinct a.answer_id) as total_answers,
           count(distinct a2.answer_id) filter (where a2.answer_score >= 1) as accepted_like_answers
    from active_questions q
    left join answers a on a.question_id = q.question_id
    left join answers a2 on a2.question_id = q.question_id and a2.score >= 1
    group by q.question_id
),
best_answer as (
    select a.question_id,
           a.answer_id,
           a.answerer_id,
           a.answer_score,
           row_number() over (partition by a.question_id order by a.answer_score desc, a.answer_created asc, a.answer_id asc) as rn
    from answers a
),
best_answer_pick as (
    select ba.question_id,
           ba.answer_id as best_answer_id,
           ba.answerer_id as best_answerer_id,
           ba.answer_score as best_answer_score
    from best_answer ba
    where ba.rn = 1
),
question_tag_ranks as (
    select te.question_id,
           min(tr.popularity_rank) as best_tag_rank,
           max(tr.popularity_rank) as worst_tag_rank,
           count(*) as tag_count
    from tag_expansion te
    join tag_rank tr on tr.tag = te.tag
    group by te.question_id
),
norms as (
    select
       (select avg(viewcount) from active_questions) as avg_views,
       (select stddev_samp(viewcount) from active_questions) as std_views,
       (select avg(question_score) from active_questions) as avg_q_score,
       (select stddev_samp(question_score) from active_questions) as std_q_score
),
final_scored as (
    select
       qe.question_id,
       qe.title,
       qe.asker_id,
       us.displayname as asker_name,
       us.reputation as asker_rep,
       coalesce(us.gold_cnt,0) as gold_cnt,
       coalesce(us.silver_cnt,0) as silver_cnt,
       coalesce(us.bronze_cnt,0) as bronze_cnt,
       coalesce(ur.posts_30d,0) as asker_posts_30d,
       qe.question_created,
       qe.question_score,
       qe.viewcount,
       qe.upvotes,
       qe.downvotes,
       qe.favorites,
       qe.bounty_total,
       qe.q_status,
       qe.last_close_reason,
       pc.total_answers,
       coalesce(bap.best_answer_id, qe.acceptedanswerid) as top_answer_id,
       bap.best_answer_score,
       qtr.best_tag_rank,
       qtr.worst_tag_rank,
       qtr.tag_count,
       round(1000
         + 0.7 * coalesce((qe.viewcount - n.avg_views) / nullif(n.std_views,0), 0)
         + 1.2 * coalesce((qe.question_score - n.avg_q_score) / nullif(n.std_q_score,0), 0)
         + 0.5 * greatest(qe.upvotes - qe.downvotes, 0)
         + 2.0 * coalesce(bap.best_answer_score, 0)
         + case when qe.q_status = 'accepted' then 25 when qe.q_status = 'answered' then 10 when qe.q_status = 'closed' then -20 else 0 end
         + case when qtr.best_tag_rank <= 50 then 15 when qtr.best_tag_rank <= 200 then 5 else 0 end
         + least(coalesce(us.reputation,0)/1000.0, 50)
         - 0.1 * coalesce(ur.asker_posts_30d,0)
       , 2) as perf_score
    from q_enriched qe
    left join user_stats us on us.user_id = qe.asker_id
    left join user_recent_activity ur on ur.user_id = qe.asker_id
    left join paired_counts pc on pc.question_id = qe.question_id
    left join best_answer_pick bap on bap.question_id = qe.question_id
    left join question_tag_ranks qtr on qtr.question_id = qe.question_id
    cross join norms n
),
ranked as (
    select fs.*,
           row_number() over (order by fs.perf_score desc, fs.viewcount desc, fs.question_created desc, fs.question_id desc) as rn,
           percent_rank() over (order by fs.perf_score desc) as perf_percentile,
           ntile(20) over (order by fs.perf_score desc) as perf_ventile
    from final_scored fs
),
with_null_logic as (
    select r.*,
           case
             when r.asker_name is null and r.asker_id is null then 'anonymous'
             when r.asker_name is null then 'deleted'
             when nullif(trim(r.asker_name), '') is null then 'blank'
             else 'named'
           end as asker_name_category,
           coalesce(nullif(r.last_close_reason, ''), 'None') as last_close_reason_norm
    from ranked r
),
de_duped as (
    select distinct on (question_id)
           question_id, title, asker_id, asker_name, asker_rep, gold_cnt, silver_cnt, bronze_cnt, asker_posts_30d,
           question_created, question_score, viewcount, upvotes, downvotes, favorites, bounty_total, q_status,
           last_close_reason_norm, total_answers, top_answer_id, best_answer_score, best_tag_rank, worst_tag_rank,
           tag_count, perf_score, rn, perf_percentile, perf_ventile, asker_name_category
    from with_null_logic
    order by question_id, rn
)
select *
from de_duped
where (perf_ventile <= 5 or (q_status <> 'closed' and perf_percentile >= 0.9))
  and coalesce(viewcount,0) > 0
  and (asker_rep is null or asker_rep >= 1 or asker_name_category in ('anonymous','deleted'))
  and (title ilike any (array['%performance%','%benchmark%','%optimiz%','%slow%']) or favorites >= 5)
order by perf_score desc, viewcount desc, question_created desc
limit 250;