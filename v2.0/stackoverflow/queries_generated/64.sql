-- {"query": "64.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3918} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
         dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
),
top_recent as (
  select ru.*
  from recent_users ru
  where ru.recency_rank <= 1000
),
user_posts as (
  select p.id,
         p.posttypeid,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.commentcount,
         p.favoritecount,
         p.closeddate,
         p.lastactivitydate
  from posts p
  where p.owneruserid is not null
),
tag_unpivot as (
  select up.id as post_id,
         up.user_id,
         unnest(string_to_array(substring(up.tags, 2, greatest(length(up.tags)-2,0)), '><')) as tag
  from user_posts up
  where up.posttypeid = 1
    and up.tags is not null
    and up.tags like '<%>'
),
user_tag_stats as (
  select t.user_id,
         count(*) filter (where t.tag is not null) as tagged_q_count,
         count(distinct t.tag) as distinct_tag_count,
         max(length(t.tag)) as max_tag_len
  from tag_unpivot t
  group by t.user_id
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_start_amt,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_close_amt,
         count(*) as total_votes
  from votes v
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comment_count,
         max(c.score) as max_comment_score,
         avg(c.score) as avg_comment_score
  from comments c
  group by c.postid
),
post_activity as (
  select up.*,
         coalesce(va.upvotes,0) as upvotes,
         coalesce(va.downvotes,0) as downvotes,
         coalesce(va.favorites,0) as favorites,
         coalesce(va.total_votes,0) as total_votes,
         coalesce(ca.comment_count,0) as comment_count_calc,
         coalesce(ca.max_comment_score,0) as max_comment_score,
         coalesce(ca.avg_comment_score,0) as avg_comment_score,
         coalesce(va.bounty_start_amt,0) - coalesce(va.bounty_close_amt,0) as bounty_net
  from user_posts up
  left join vote_agg va on va.postid = up.id
  left join comment_agg ca on ca.postid = up.id
),
question_answer_map as (
  select q.id as question_id,
         a.id as answer_id,
         a.owneruserid as answerer_id,
         a.score as answer_score,
         a.creationdate as answer_date
  from posts q
  join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
accepted_answers as (
  select q.id as question_id,
         q.acceptedanswerid as answer_id
  from posts q
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
),
qa_stats as (
  select qam.question_id,
         count(*) as answer_count,
         sum(case when qam.answer_score > 0 then 1 else 0 end) as positive_answers,
         max(qam.answer_score) as max_answer_score,
         sum(case when aa.answer_id is not null and aa.answer_id = qam.answer_id then 1 else 0 end) as accepted_present
  from question_answer_map qam
  left join accepted_answers aa on aa.question_id = qam.question_id and aa.answer_id = qam.answer_id
  group by qam.question_id
),
post_closure as (
  select ph.postid,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopened_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
         max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
  from posthistory ph
  group by ph.postid
),
user_level as (
  select u.id as user_id,
         case
           when u.reputation >= 100000 then 'Legend'
           when u.reputation >= 20000 then 'Guru'
           when u.reputation >= 5000 then 'Expert'
           when u.reputation >= 1000 then 'Contributor'
           else 'Newbie'
         end as rep_band,
         width_bucket(u.reputation, 0, 100000, 10) as rep_bucket
  from users u
),
user_badges as (
  select b.userid as user_id,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
dup_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as target_post_id,
         pl.creationdate,
         pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
question_meta as (
  select p.id as post_id,
         p.owneruserid as user_id,
         lower(coalesce(p.title,'')) as title_lc,
         p.viewcount,
         p.score,
         p.favoritecount,
         (p.viewcount::numeric / nullif(greatest(extract(epoch from age(now(), p.creationdate)) / 3600.0, 1),0)) as views_per_hour,
         (p.score::numeric / nullif(greatest(extract(epoch from age(now(), p.creationdate)) / 3600.0, 1),0)) as score_per_hour,
         case when p.tags ilike '%<sql>%' then 1 else 0 end as has_sql_tag
  from posts p
  where p.posttypeid = 1
),
user_post_rollup as (
  select pa.user_id,
         count(*) as total_posts,
         count(*) filter (where pa.posttypeid = 1) as total_questions,
         count(*) filter (where pa.posttypeid = 2) as total_answers,
         sum(pa.upvotes) as total_upvotes,
         sum(pa.downvotes) as total_downvotes,
         sum(case when pa.posttypeid = 1 then pa.viewcount else 0 end) as total_question_views,
         sum(pa.bounty_net) as total_bounty_net,
         sum(case when pa.posttypeid = 1 then 1 else 0 end) filter (where pa.closeddate is not null) as closed_questions
  from post_activity pa
  group by pa.user_id
),
title_tokens as (
  select qm.post_id,
         regexp_split_to_table(regexp_replace(qm.title_lc, '[^a-z0-9]+', ' ', 'g'), '\s+') as token
  from question_meta qm
),
title_tf as (
  select post_id, token, count(*) as tf
  from title_tokens
  where token <> ''
  group by post_id, token
),
corpus_df as (
  select token, count(distinct post_id) as df
  from title_tf
  group by token
),
idf as (
  select df.token,
         1 + ln((select count(distinct post_id) from title_tf)::numeric / greatest(df.df,1)) as idf_val
  from corpus_df df
),
tfidf as (
  select tf.post_id,
         sum(tf.tf * i.idf_val) as title_tfidf
  from title_tf tf
  join idf i on i.token = tf.token
  group by tf.post_id
),
user_question_quality as (
  select qm.user_id,
         avg(qm.score) as avg_q_score,
         avg(qm.viewcount) as avg_q_views,
         avg(qm.score_per_hour) as avg_q_sph,
         avg(qm.views_per_hour) as avg_q_vph,
         sum(case when qs.answer_count is null then 0 else qs.answer_count end) as total_answers_received,
         sum(case when qs.accepted_present > 0 then 1 else 0 end) as questions_with_accept,
         sum(qm.has_sql_tag) as sql_tagged_q
  from question_meta qm
  left join qa_stats qs on qs.question_id = qm.post_id
  group by qm.user_id
),
user_dup_behavior as (
  select q.owneruserid as user_id,
         count(*) filter (where d.dup_post_id is not null) as dup_count_as_source,
         count(*) filter (where d.target_post_id is not null) as dup_count_as_target
  from posts q
  left join dup_links d on d.dup_post_id = q.id
  where q.posttypeid = 1
  group by q.owneruserid
),
close_reason_map as (
  select crt.id as close_reason_id, crt.name as close_reason_name
  from closereasontypes crt
),
post_last_close_reason as (
  select pc.postid,
         coalesce(crm.close_reason_name, 'Unknown') as last_close_reason_name
  from post_closure pc
  left join close_reason_map crm on crm.close_reason_id = pc.last_close_reason_id
),
user_last_close_mix as (
  select p.owneruserid as user_id,
         count(*) as total_closed,
         count(*) filter (where plcr.last_close_reason_name ilike '%duplicate%') as closed_as_dup,
         count(*) filter (where plcr.last_close_reason_name ilike '%off%topic%') as closed_as_offtopic
  from posts p
  join post_last_close_reason plcr on plcr.postid = p.id
  where p.posttypeid = 1
  group by p.owneruserid
),
baseline as (
  select tr.user_id,
         tr.displayname,
         tr.reputation,
         tr.creationdate,
         tr.location,
         tr.websiteurl_norm
  from top_recent tr
),
assembled as (
  select
    b.user_id,
    b.displayname,
    b.reputation,
    ul.rep_band,
    ul.rep_bucket,
    coalesce(upr.total_posts,0) as total_posts,
    coalesce(upr.total_questions,0) as total_questions,
    coalesce(upr.total_answers,0) as total_answers,
    coalesce(upr.total_upvotes,0) as total_upvotes,
    coalesce(upr.total_downvotes,0) as total_downvotes,
    coalesce(upr.total_question_views,0) as total_question_views,
    coalesce(upr.total_bounty_net,0) as total_bounty_net,
    coalesce(upr.closed_questions,0) as closed_questions,
    coalesce(uts.tagged_q_count,0) as tagged_q_count,
    coalesce(uts.distinct_tag_count,0) as distinct_tag_count,
    coalesce(uts.max_tag_len,0) as max_tag_len,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    coalesce(ub.tag_badges,0) as tag_badges,
    coalesce(uqq.avg_q_score,0) as avg_q_score,
    coalesce(uqq.avg_q_views,0) as avg_q_views,
    coalesce(uqq.avg_q_sph,0) as avg_q_sph,
    coalesce(uqq.avg_q_vph,0) as avg_q_vph,
    coalesce(uqq.total_answers_received,0) as total_answers_received,
    coalesce(uqq.questions_with_accept,0) as questions_with_accept,
    coalesce(uqq.sql_tagged_q,0) as sql_tagged_q,
    coalesce(udb.dup_count_as_source,0) as dup_count_as_source,
    coalesce(udb.dup_count_as_target,0) as dup_count_as_target,
    coalesce(ulcr.total_closed,0) as total_closed_by_reason,
    coalesce(ulcr.closed_as_dup,0) as closed_as_dup,
    coalesce(ulcr.closed_as_offtopic,0) as closed_as_offtopic
  from baseline b
  left join user_level ul on ul.user_id = b.user_id
  left join user_post_rollup upr on upr.user_id = b.user_id
  left join user_tag_stats uts on uts.user_id = b.user_id
  left join user_badges ub on ub.user_id = b.user_id
  left join user_question_quality uqq on uqq.user_id = b.user_id
  left join user_dup_behavior udb on udb.user_id = b.user_id
  left join user_last_close_mix ulcr on ulcr.user_id = b.user_id
),
ranked as (
  select a.*,
         row_number() over (
           partition by a.rep_band
           order by (a.total_upvotes - a.total_downvotes) desc nulls last, a.avg_q_sph desc nulls last, a.total_posts desc
         ) as band_rank,
         rank() over (order by (a.total_upvotes - a.total_downvotes) desc nulls last) as global_rank
  from assembled a
),
user_latest_activity as (
  select p.owneruserid as user_id,
         max(p.lastactivitydate) as last_post_activity,
         max(c.creationdate) as last_comment_activity
  from posts p
  left join comments c on c.postid = p.id
  group by p.owneruserid
),
final_scores as (
  select r.*,
         coalesce(ula.last_post_activity, timestamp '1970-01-01') as last_post_activity,
         coalesce(ula.last_comment_activity, timestamp '1970-01-01') as last_comment_activity,
         (0.4 * nullif(r.total_upvotes - r.total_downvotes,0)
          + 0.2 * r.total_answers
          + 0.2 * r.total_questions
          + 0.1 * r.gold_badges
          + 0.05 * r.silver_badges
          + 0.02 * r.bronze_badges
          + 0.03 * r.distinct_tag_count) as composite_score
  from ranked r
  left join user_latest_activity ula on ula.user_id = r.user_id
),
norm as (
  select f.*,
         (f.composite_score - min(f.composite_score) over ()) /
         nullif(max(f.composite_score) over () - min(f.composite_score) over (), 0) as composite_norm
  from final_scores f
)
select
  n.user_id,
  n.displayname,
  n.reputation,
  n.rep_band,
  n.rep_bucket,
  n.global_rank,
  n.band_rank,
  n.total_posts,
  n.total_questions,
  n.total_answers,
  n.total_upvotes,
  n.total_downvotes,
  n.total_question_views,
  n.total_bounty_net,
  n.closed_questions,
  n.tagged_q_count,
  n.distinct_tag_count,
  n.max_tag_len,
  n.total_badges,
  n.gold_badges,
  n.silver_badges,
  n.bronze_badges,
  n.tag_badges,
  round(n.avg_q_score::numeric, 2) as avg_q_score,
  round(n.avg_q_views::numeric, 2) as avg_q_views,
  round(n.avg_q_sph::numeric, 4) as avg_q_sph,
  round(n.avg_q_vph::numeric, 4) as avg_q_vph,
  n.total_answers_received,
  n.questions_with_accept,
  n.sql_tagged_q,
  n.dup_count_as_source,
  n.dup_count_as_target,
  n.total_closed_by_reason,
  n.closed_as_dup,
  n.closed_as_offtopic,
  n.last_post_activity,
  n.last_comment_activity,
  round(n.composite_score::numeric, 2) as composite_score,
  round(coalesce(n.composite_norm, 0)::numeric, 4) as composite_norm,
  case
    when n.websiteurl_norm ilike '%github.com%' then 'GitHub'
    when n.websiteurl_norm ilike '%linkedin.com%' then 'LinkedIn'
    when n.websiteurl_norm ilike '%twitter.com%' or n.websiteurl_norm ilike '%x.com%' then 'Twitter'
    when n.websiteurl_norm = 'N/A' then 'None'
    else 'Other'
  end as website_category
from norm n
where (
    n.total_posts > 0
    or exists (
      select 1
      from posts p
      where p.owneruserid = n.user_id
        and p.creationdate > now() - interval '365 days'
    )
  )
order by n.global_rank, n.band_rank, n.user_id
limit 200;