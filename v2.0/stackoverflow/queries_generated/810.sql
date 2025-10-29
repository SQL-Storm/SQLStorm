-- {"query": "810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3426} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as website_norm,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '12 months' from posts p)
),
question_posts as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.favoritecount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.closeddate,
           p.posttypeid
    from posts p
    where p.posttypeid = 1
),
user_q_stats as (
    select ru.user_id,
           count(q.id) filter (where q.creationdate >= ru.creationdate) as questions_since_join,
           sum(case when q.closeddate is not null then 1 else 0 end) as closed_q,
           avg(nullif(q.score,0)) as avg_nonzero_score,
           percentile_cont(0.5) within group (order by q.viewcount) as median_views,
           count(*) as total_q,
           sum(coalesce(q.favoritecount,0)) as total_favs
    from recent_users ru
    left join question_posts q
      on q.owneruserid = ru.user_id
    group by ru.user_id
),
answer_posts as (
    select p.id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
user_a_stats as (
    select ru.user_id,
           count(a.id) as total_a,
           sum(case when a.score > 0 then 1 else 0 end) as pos_a,
           sum(case when a.score < 0 then 1 else 0 end) as neg_a,
           max(a.score) as max_a_score,
           min(a.score) as min_a_score,
           avg(a.score) as avg_a_score
    from recent_users ru
    left join answer_posts a
      on a.user_id = ru.user_id
    group by ru.user_id
),
badge_mix as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           count(*) as badge_total,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
q_linkage as (
    select q.id as question_id,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_links
    from question_posts q
    left join postlinks pl
      on pl.postid = q.id
    group by q.id
),
q_hist_flags as (
    select ph.postid as question_id,
           sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_events,
           max(case when ph.posthistorytypeid in (10,35) then ph.creationdate end) as last_closed_at,
           sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
           sum(case when ph.posthistorytypeid in (19) then 1 else 0 end) as protected_events,
           sum(case when ph.posthistorytypeid in (50) then 1 else 0 end) as community_bumps
    from posthistory ph
    where ph.postid in (select id from question_posts)
    group by ph.postid
),
comment_sentiment as (
    select c.postid,
           avg(c.score) as avg_comment_score,
           sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_cnt,
           sum(case when position('sorry' in lower(c.text)) > 0 then 1 else 0 end) as sorry_cnt,
           count(*) as comment_cnt
    from comments c
    group by c.postid
),
tag_expansion as (
    select q.id as question_id,
           unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from question_posts q
    where q.tags is not null and length(q.tags) >= 2
),
user_top_tags as (
    select q.owneruserid as user_id,
           t.tag,
           count(*) as tag_count,
           row_number() over (partition by q.owneruserid order by count(*) desc, min(q.creationdate)) as tag_rank
    from tag_expansion t
    join posts q on q.id = t.question_id
    group by q.owneruserid, t.tag
),
user_primary_tag as (
    select user_id,
           tag as primary_tag,
           tag_count
    from user_top_tags
    where tag_rank = 1
),
user_activity as (
    select ru.user_id,
           count(*) filter (where p.posttypeid = 1) as q_posts,
           count(*) filter (where p.posttypeid = 2) as a_posts,
           count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_posts,
           max(p.lastactivitydate) as last_post_activity
    from recent_users ru
    left join posts p
      on p.owneruserid = ru.user_id
    group by ru.user_id
),
question_quality as (
    select q.id as question_id,
           q.owneruserid as user_id,
           q.score,
           q.viewcount,
           q.favoritecount,
           coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
           case
             when q.score >= 10 and q.viewcount >= 10000 then 'viral'
             when q.score >= 5 and q.viewcount >= 2000 then 'popular'
             when q.score <= 0 and coalesce(v.downvotes,0) > coalesce(v.upvotes,0) then 'controversial'
             else 'normal'
           end as quality_bucket
    from question_posts q
    left join vote_agg v on v.postid = q.id
),
accepted_answer_latency as (
    select q.id as question_id,
           extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1 and q.acceptedanswerid is not null
),
user_rollup as (
    select
      ru.user_id,
      ru.displayname,
      ru.reputation,
      ru.creationdate,
      ru.location,
      ru.website_norm,
      ua.total_a,
      ua.pos_a,
      ua.neg_a,
      ua.max_a_score,
      ua.min_a_score,
      ua.avg_a_score,
      uq.total_q,
      uq.questions_since_join,
      uq.closed_q,
      uq.avg_nonzero_score,
      uq.median_views,
      uq.total_favs,
      ub.gold,
      ub.silver,
      ub.bronze,
      ub.badge_total,
      ub.tag_badges,
      ut.primary_tag,
      ut.tag_count as primary_tag_count,
      act.q_posts,
      act.a_posts,
      act.other_posts,
      act.last_post_activity
    from recent_users ru
    left join user_q_stats uq on uq.user_id = ru.user_id
    left join user_a_stats ua on ua.user_id = ru.user_id
    left join badge_mix ub on ub.user_id = ru.user_id
    left join user_primary_tag ut on ut.user_id = ru.user_id
    left join user_activity act on act.user_id = ru.user_id
),
question_enriched as (
    select
      q.id,
      q.owneruserid as user_id,
      q.title,
      q.tags,
      q.creationdate,
      q.score,
      q.viewcount,
      coalesce(qf.quality_bucket, 'normal') as quality_bucket,
      coalesce(ql.dup_links,0) as dup_links,
      coalesce(ql.linked_links,0) as linked_links,
      coalesce(qh.close_events,0) as close_events,
      qh.last_closed_at,
      coalesce(qh.reopen_events,0) as reopen_events,
      coalesce(qh.protected_events,0) as protected_events,
      coalesce(qh.community_bumps,0) as community_bumps,
      coalesce(cs.avg_comment_score,0.0) as avg_comment_score,
      coalesce(cs.thanks_cnt,0) as thanks_cnt,
      coalesce(cs.sorry_cnt,0) as sorry_cnt,
      coalesce(cs.comment_cnt,0) as comment_cnt,
      aal.hours_to_accept
    from question_posts q
    left join q_linkage ql on ql.question_id = q.id
    left join q_hist_flags qh on qh.question_id = q.id
    left join comment_sentiment cs on cs.postid = q.id
    left join question_quality qf on qf.question_id = q.id
    left join accepted_answer_latency aal on aal.question_id = q.id
),
user_question_rank as (
    select
      qe.user_id,
      qe.id as question_id,
      row_number() over (partition by qe.user_id order by coalesce(qe.score,0) desc, coalesce(qe.viewcount,0) desc, qe.id) as q_rank,
      rank() over (partition by qe.user_id order by coalesce(qe.hours_to_accept, 1e9)) as fast_accept_rank
    from question_enriched qe
),
similar_user_detection as (
    select r1.user_id as user_a,
           r2.user_id as user_b,
           abs(coalesce(r1.reputation,0) - coalesce(r2.reputation,0)) as rep_gap,
           abs(coalesce(r1.total_q,0) - coalesce(r2.total_q,0)) as q_gap,
           abs(coalesce(r1.total_a,0) - coalesce(r2.total_a,0)) as a_gap,
           (coalesce(r1.primary_tag,'') = coalesce(r2.primary_tag,'')) as same_primary_tag
    from user_rollup r1
    join user_rollup r2
      on r1.user_id < r2.user_id
     and abs(coalesce(r1.reputation,0) - coalesce(r2.reputation,0)) < 1000
     and abs(coalesce(r1.total_q,0) - coalesce(r2.total_q,0)) <= 10
     and abs(coalesce(r1.total_a,0) - coalesce(r2.total_a,0)) <= 20
),
final_user_scores as (
    select
      ur.*,
      coalesce(ur.total_q,0) + coalesce(ur.total_a,0) as total_posts,
      (case
         when coalesce(ur.badge_total,0) = 0 then null
         else (coalesce(ur.gold,0)*5 + coalesce(ur.silver,0)*3 + coalesce(ur.bronze,0)*1)::float / nullif(ur.badge_total,0)
       end) as badge_weighted_score,
      coalesce(ur.avg_a_score,0) * 0.5 + coalesce(ur.avg_nonzero_score,0) * 0.5 as blended_avg_score,
      case
        when ur.website_norm ilike '%github%' then 1
        when ur.website_norm ilike '%gitlab%' then 1
        when ur.website_norm ilike '%bitbucket%' then 1
        else 0
      end as has_code_site
    from user_rollup ur
),
question_outliers as (
    select
      qe.*,
      case
        when qe.viewcount >= (select percentile_cont(0.99) within group (order by coalesce(viewcount,0)) from question_posts) then 1 else 0
      end as view_outlier,
      case
        when qe.score >= (select percentile_cont(0.99) within group (order by coalesce(score,0)) from question_posts) then 1 else 0
      end as score_outlier
    from question_enriched qe
),
user_kpis as (
    select
      fus.user_id,
      count(qe.id) filter (where qe.quality_bucket = 'viral') as viral_q,
      count(qe.id) filter (where qe.quality_bucket = 'popular') as popular_q,
      count(qe.id) filter (where qe.close_events > 0) as closed_q_cnt,
      avg(qe.hours_to_accept) as avg_hours_to_accept,
      sum(qe.comment_cnt) as comments_on_questions
    from final_user_scores fus
    left join question_enriched qe on qe.user_id = fus.user_id
    group by fus.user_id
)
select
  fus.user_id,
  fus.displayname,
  fus.reputation,
  fus.creationdate,
  fus.location,
  fus.primary_tag,
  fus.total_posts,
  fus.q_posts,
  fus.a_posts,
  fus.badge_total,
  fus.badge_weighted_score,
  fus.blended_avg_score,
  fus.has_code_site,
  uk.viral_q,
  uk.popular_q,
  uk.closed_q_cnt,
  uk.avg_hours_to_accept,
  uk.comments_on_questions,
  coalesce(sim_cnt.similar_count, 0) as similar_users,
  top_q.id as top_question_id,
  top_q.title as top_question_title,
  top_q.score as top_question_score,
  top_q.viewcount as top_question_views,
  top_q.quality_bucket as top_question_quality,
  fast_q.id as fastest_accept_qid,
  fast_q.hours_to_accept as fastest_accept_hours
from final_user_scores fus
left join user_kpis uk on uk.user_id = fus.user_id
left join (
    select uqr.user_id, uqr.question_id
    from user_question_rank uqr
    where uqr.q_rank = 1
) tq on tq.user_id = fus.user_id
left join question_enriched top_q on top_q.id = tq.question_id
left join (
    select uqr.user_id, uqr.question_id
    from user_question_rank uqr
    where uqr.fast_accept_rank = 1
) fq on fq.user_id = fus.user_id
left join question_enriched fast_q on fast_q.id = fq.question_id
left join (
    select su.user_a as user_id, count(*) as similar_count
    from similar_user_detection su
    group by su.user_a
) sim_cnt on sim_cnt.user_id = fus.user_id
where coalesce(fus.total_posts,0) > 0
order by
  coalesce(fus.reputation,0) desc,
  coalesce(fus.total_posts,0) desc,
  fus.user_id
limit 500;