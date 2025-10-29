-- {"query": "589.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2981}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain_host,
         row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
q_and_a as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.tags,
         p.title,
         p.acceptedanswerid,
         p.parentid
  from posts p
  where p.posttypeid in (1,2)
),
user_posts as (
  select ru.user_id,
         count(*) filter (where qa.posttypeid = 1) as questions,
         count(*) filter (where qa.posttypeid = 2) as answers,
         sum(qa.score) as total_score,
         avg(nullif(qa.score,0)) as avg_nonzero_score,
         max(qa.viewcount) as max_views,
         min(qa.creationdate) as first_post_date,
         max(qa.creationdate) as last_post_date
  from recent_users ru
  left join q_and_a qa
    on qa.owneruserid = ru.user_id
  group by ru.user_id
),
tag_extract as (
  select qa.id as post_id,
         unnest(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><')) as tagname
  from q_and_a qa
  where qa.posttypeid = 1
    and qa.tags is not null
),
top_tags as (
  select te.tagname,
         count(*) as tag_q_count,
         row_number() over (order by count(*) desc, tagname) as tag_rank
  from tag_extract te
  group by te.tagname
),
user_badges as (
  select b.userid as user_id,
         count(*) as total_badges,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) filter (where coalesce(b.tagbased, false) = true) as tag_badges,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
comment_activity as (
  select c.userid as user_id,
         count(*) as comments_made,
         sum(c.score) as comment_score,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
vote_agg as (
  select v.userid as user_id,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
         sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_sum,
         min(v.creationdate) as first_vote_date,
         max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
post_closure as (
  select ph.postid,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
         count(*) filter (where ph.posthistorytypeid in (33,34)) as notice_events
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select pl.postid,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         max(pl.creationdate) filter (where pl.linktypeid = 3) as last_dup_link_at
  from postlinks pl
  group by pl.postid
),
question_health as (
  select qa.id as question_id,
         qa.owneruserid as user_id,
         qa.creationdate as asked_at,
         qa.score,
         qa.viewcount,
         qa.answercount,
         pc.first_closed_at,
         pc.last_reopened_at,
         pc.close_events,
         pc.reopen_events,
         dl.duplicate_links,
         case
           when pc.first_closed_at is not null and pc.reopen_events > 0 then 'closed-reopened'
           when pc.first_closed_at is not null then 'closed'
           when dl.duplicate_links > 0 then 'duplicate-linked'
           else 'open'
         end as status_label
  from q_and_a qa
  left join post_closure pc on pc.postid = qa.id
  left join dup_links dl on dl.postid = qa.id
  where qa.posttypeid = 1
),
accepted_vs_owned as (
  select qa.owneruserid as user_id,
         count(*) filter (where qa.posttypeid = 1 and qa.acceptedanswerid is not null) as questions_with_accept,
         count(*) filter (where qa.posttypeid = 1) as total_questions,
         count(*) filter (
           where qa.posttypeid = 2 and exists (
             select 1
             from posts q
             where q.id = qa.parentid
               and q.acceptedanswerid = qa.id
           )
         ) as accepted_answers_authored
  from q_and_a qa
  group by qa.owneruserid
),
cross_tag_activity as (
  select qa.owneruserid as user_id,
         count(distinct te.tagname) as distinct_tags_asked,
         max(te.tagname) filter (where tt.tag_rank <= 10) as example_top_tag,
         sum(case when tt.tag_rank <= 50 then 1 else 0 end) as top50_tag_questions
  from q_and_a qa
  left join tag_extract te on te.post_id = qa.id
  left join top_tags tt on tt.tagname = te.tagname
  where qa.posttypeid = 1
  group by qa.owneruserid
),
user_activity_span as (
  select u.id as user_id,
         min(p.creationdate) as first_activity,
         max(p.creationdate) as last_activity,
         extract(epoch from (max(p.creationdate) - min(p.creationdate))) / 86400.0 as active_days_span
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
ranked_users as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location,
         ru.domain_host,
         up.questions,
         up.answers,
         up.total_score,
         coalesce(up.avg_nonzero_score, 0) as avg_nonzero_score,
         up.max_views,
         ub.total_badges,
         ub.gold_badges,
         ub.silver_badges,
         ub.bronze_badges,
         ub.tag_badges,
         coalesce(ca.comments_made,0) as comments_made,
         coalesce(ca.comment_score,0) as comment_score,
         coalesce(va.upvotes_cast,0) as upvotes_cast,
         coalesce(va.downvotes_cast,0) as downvotes_cast,
         coalesce(va.bounties_interactions,0) as bounties_interactions,
         coalesce(va.bounty_amount_sum,0) as bounty_amount_sum,
         coalesce(av.accepted_answers_authored,0) as accepted_answers_authored,
         coalesce(av.total_questions,0) as total_questions,
         coalesce(av.questions_with_accept,0) as questions_with_accept,
         coalesce(ct.distinct_tags_asked,0) as distinct_tags_asked,
         coalesce(ct.example_top_tag,'') as example_top_tag,
         coalesce(ct.top50_tag_questions,0) as top50_tag_questions,
         uas.active_days_span,
         count(qh.question_id) filter (where qh.status_label in ('closed','closed-reopened')) as closed_questions,
         count(qh.question_id) filter (where qh.status_label = 'duplicate-linked') as duplicate_linked_questions,
         count(qh.question_id) filter (where qh.status_label = 'open') as open_questions,
         percentile_cont(0.5) within group (order by qh.viewcount) as median_q_views,
         sum(qh.score) as question_score_sum,
         sum(qh.answercount) as question_answer_sum,
         row_number() over (
           order by
             coalesce(up.total_score,0) desc,
             coalesce(ub.total_badges,0) desc,
             ru.reputation desc,
             ru.user_id
         ) as perf_rank
  from recent_users ru
  left join user_posts up on up.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join comment_activity ca on ca.user_id = ru.user_id
  left join vote_agg va on va.user_id = ru.user_id
  left join accepted_vs_owned av on av.user_id = ru.user_id
  left join cross_tag_activity ct on ct.user_id = ru.user_id
  left join user_activity_span uas on uas.user_id = ru.user_id
  left join question_health qh on qh.user_id = ru.user_id
  group by
    ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.domain_host,
    up.questions, up.answers, up.total_score, up.avg_nonzero_score, up.max_views,
    ub.total_badges, ub.gold_badges, ub.silver_badges, ub.bronze_badges, ub.tag_badges,
    ca.comments_made, ca.comment_score,
    va.upvotes_cast, va.downvotes_cast, va.bounties_interactions, va.bounty_amount_sum,
    av.accepted_answers_authored, av.total_questions, av.questions_with_accept,
    ct.distinct_tags_asked, ct.example_top_tag, ct.top50_tag_questions,
    uas.active_days_span
),
bench_sample as (
  select *
  from ranked_users
  where
    (questions + answers + comments_made + upvotes_cast + downvotes_cast) > 0
    and coalesce(location,'') not ilike '%test%'
    and (reputation > 0 or total_badges > 0 or total_score > 0)
),
paired_compare as (
  select a.user_id as user_id_a,
         b.user_id as user_id_b,
         a.perf_rank as rank_a,
         b.perf_rank as rank_b,
         abs(a.perf_rank - b.perf_rank) as rank_distance,
         (coalesce(a.total_score,0) - coalesce(b.total_score,0)) as score_delta,
         (coalesce(a.total_badges,0) - coalesce(b.total_badges,0)) as badges_delta,
         (coalesce(a.accepted_answers_authored,0) - coalesce(b.accepted_answers_authored,0)) as accepted_delta
  from bench_sample a
  join bench_sample b
    on a.user_id < b.user_id
   and (a.domain_host is not distinct from b.domain_host)
   and abs(a.reputation - b.reputation) <= 1000
   and abs(coalesce(a.active_days_span,0) - coalesce(b.active_days_span,0)) <= 365
   and (a.distinct_tags_asked is not distinct from b.distinct_tags_asked or greatest(a.distinct_tags_asked, b.distinct_tags_asked) <= 5)
),
agg_pairs as (
  select
    count(*) as pairs_considered,
    avg(rank_distance) as avg_rank_distance,
    percentile_cont(0.9) within group (order by rank_distance) as p90_rank_distance,
    sum(case when score_delta * badges_delta < 0 then 1 else 0 end) as contradictory_pairs,
    avg(abs(score_delta)) as avg_abs_score_delta,
    avg(abs(badges_delta)) as avg_abs_badges_delta
  from paired_compare
)
select
  bs.user_id,
  bs.displayname,
  bs.reputation,
  bs.domain_host,
  bs.questions,
  bs.answers,
  bs.total_score,
  bs.avg_nonzero_score,
  bs.max_views,
  bs.total_badges,
  bs.gold_badges,
  bs.silver_badges,
  bs.bronze_badges,
  bs.tag_badges,
  bs.comments_made,
  bs.comment_score,
  bs.upvotes_cast,
  bs.downvotes_cast,
  bs.bounties_interactions,
  bs.bounty_amount_sum,
  bs.accepted_answers_authored,
  bs.total_questions,
  bs.questions_with_accept,
  bs.distinct_tags_asked,
  bs.example_top_tag,
  bs.top50_tag_questions,
  bs.active_days_span,
  bs.closed_questions,
  bs.duplicate_linked_questions,
  bs.open_questions,
  bs.median_q_views,
  bs.question_score_sum,
  bs.question_answer_sum,
  bs.perf_rank,
  ap.pairs_considered,
  ap.avg_rank_distance,
  ap.p90_rank_distance,
  ap.contradictory_pairs,
  ap.avg_abs_score_delta,
  ap.avg_abs_badges_delta
from bench_sample bs
cross join agg_pairs ap
where bs.perf_rank <= 200
order by bs.perf_rank, bs.user_id;