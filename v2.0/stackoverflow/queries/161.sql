-- {"query": "161.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3473}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''), '/', 3)), ''), 'no-domain') as website_domain,
         row_number() over (order by u.creationdate desc, u.id) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    u.user_id,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
    count(distinct p.id) filter (where p.posttypeid = 1) as question_count,
    count(distinct p.id) filter (where p.posttypeid = 2) as answer_count,
    sum(greatest(p.score,0)) as nonneg_score_sum,
    avg(nullif(p.viewcount,0)) as avg_viewcount_nonzero,
    sum(c.score) as comment_score_sum,
    count(c.id) as comment_count
  from recent_users u
  left join posts p
    on p.owneruserid = u.user_id
  left join comments c
    on c.userid = u.user_id
  group by u.user_id
),
accepted_answers as (
  select a.owneruserid as user_id,
         count(*) as accepted_answers,
         count(*) filter (where a.score >= 5) as accepted_high_score
  from posts q
  join posts a
    on a.id = q.acceptedanswerid
   and a.posttypeid = 2
  where q.posttypeid = 1
  group by a.owneruserid
),
bounty_stats as (
  select p.owneruserid as user_id,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_earned,
         count(*) filter (where v.votetypeid in (8,9)) as bounty_votes
  from votes v
  join posts p on p.id = v.postid
  group by p.owneruserid
),
badge_classes as (
  select b.userid as user_id,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) filter (where CASE WHEN b.tagbased THEN 1 ELSE 0 END = 1) as tag_badges
  from badges b
  group by b.userid, b.tagbased
),
question_tag_expansion as (
  select p.id as post_id,
         p.owneruserid as user_id,
         unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
),
top_tags as (
  select qte.user_id,
         string_agg(t.tagname, ',' order by t.count desc nulls last, t.tagname) as top_tags_by_popularity,
         count(*) as tag_mentions
  from question_tag_expansion qte
  join tags t on lower(t.tagname) = lower(qte.tagname)
  group by qte.user_id
),
closed_questions as (
  select p.owneruserid as user_id,
         count(*) as closed_q_count,
         min(p.closeddate) as first_closed_date
  from posts p
  where p.posttypeid = 1 and p.closeddate is not null
  group by p.owneruserid
),
edit_events as (
  select ph.userid as user_id,
         count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
         count(*) filter (where ph.posthistorytypeid in (24)) as suggested_applied,
         count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_recorded
  from posthistory ph
  group by ph.userid
),
linking as (
  select p.owneruserid as user_id,
         count(*) filter (where pl.linktypeid = 1) as links_created,
         count(*) filter (where pl.linktypeid = 3) as marked_duplicate
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
post_quality as (
  select p.owneruserid as user_id,
         percentile_cont(0.5) within group (order by p.score) as median_post_score,
         avg(p.score) as avg_post_score,
         stddev_pop(p.score) as stddev_post_score,
         max(p.score) as max_post_score,
         min(p.score) as min_post_score
  from posts p
  where p.posttypeid in (1,2)
  group by p.owneruserid
),
activity_window as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) as posts_in_month,
    sum(p.score) as score_in_month
  from posts p
  where p.posttypeid in (1,2)
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_rank as (
  select
    aw.user_id,
    aw.month,
    aw.posts_in_month,
    aw.score_in_month,
    rank() over (partition by aw.user_id order by aw.posts_in_month desc, aw.score_in_month desc, aw.month desc) as month_rank
  from activity_window aw
),
domain_peers as (
  select ru.user_id,
         count(*) over (partition by ru.website_domain) as domain_user_count,
         avg(ru.reputation) over (partition by ru.website_domain) as domain_avg_rep
  from recent_users ru
),
correlated_metrics as (
  select ru.user_id,
         (select count(*) from posts p where p.owneruserid = ru.user_id and coalesce(p.score,0) > 0) as pos_posts,
         (select count(*) from posts p where p.owneruserid = ru.user_id and coalesce(p.score,0) < 0) as neg_posts,
         (select count(*) from comments c where c.userid = ru.user_id and c.score > 0) as pos_comments,
         (select count(*) from comments c where c.userid = ru.user_id and c.score < 0) as neg_comments
  from recent_users ru
),
hotness as (
  select p.owneruserid as user_id,
         sum(case when ph.posthistorytypeid in (52) then 1 else 0 end) as times_hot,
         sum(case when ph.posthistorytypeid in (53) then 1 else 0 end) as times_unhot
  from posts p
  left join posthistory ph on ph.postid = p.id
  group by p.owneruserid
),
reopen_flow as (
  select p.owneruserid as user_id,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes_recorded
  from posts p
  left join posthistory ph on ph.postid = p.id
  group by p.owneruserid
),
vote_agg as (
  select p.owneruserid as user_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received
  from votes v
  join posts p on p.id = v.postid
  group by p.owneruserid
),
comment_length as (
  select c.userid as user_id,
         avg(length(c.text)) as avg_comment_len,
         max(length(c.text)) as max_comment_len
  from comments c
  group by c.userid
),
title_quality as (
  select p.owneruserid as user_id,
         avg(nullif(length(coalesce(p.title,'')),0)) as avg_title_len,
         sum(case when position('?' in coalesce(p.title,'')) > 0 then 1 else 0 end) as titles_with_question_mark
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
dup_network as (
  select p.owneruserid as user_id,
         count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as distinct_dupe_targets
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
rankings as (
  select
    ru.user_id,
    ua.total_posts,
    ua.question_count,
    ua.answer_count,
    coalesce(aa.accepted_answers,0) as accepted_answers,
    coalesce(v.upvotes_received,0) as upvotes_received,
    coalesce(v.downvotes_received,0) as downvotes_received,
    dense_rank() over (order by coalesce(aa.accepted_answers,0) desc, coalesce(v.upvotes_received,0) desc, ua.answer_count desc) as answerer_rank,
    dense_rank() over (order by ua.question_count desc, coalesce(cq.closed_q_count,0) asc nulls last, coalesce(pq.avg_post_score,0) desc) as asker_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join accepted_answers aa on aa.user_id = ru.user_id
  left join vote_agg v on v.user_id = ru.user_id
  left join closed_questions cq on cq.user_id = ru.user_id
  left join post_quality pq on pq.user_id = ru.user_id
),
activity_extremes as (
  select
    user_id,
    max(case when month_rank = 1 then posts_in_month end) as best_month_posts,
    max(case when month_rank = 1 then score_in_month end) as best_month_score
  from activity_rank
  group by user_id
),
stringiness as (
  select ru.user_id,
         trim(both from coalesce(ru.location, 'unknown')) as cleaned_location,
         upper(left(coalesce(ru.displayname, 'anon'), 1)) as display_initial,
         case when ru.displayname ilike '%bot%' then 1 else 0 end as maybe_bot_flag
  from recent_users ru
)
select
  ru.user_id,
  ru.displayname,
  ru.reputation,
  ru.creationdate,
  ru.website_domain,
  de.domain_user_count,
  round(coalesce(de.domain_avg_rep,0),2) as domain_avg_rep,
  ua.total_posts,
  ua.question_count,
  ua.answer_count,
  ua.nonneg_score_sum,
  round(cast(ua.avg_viewcount_nonzero as numeric),2) as avg_viewcount_nonzero,
  coalesce(aa.accepted_answers,0) as accepted_answers,
  coalesce(aa.accepted_high_score,0) as accepted_high_score,
  coalesce(bs.bounty_started,0) as bounty_started,
  coalesce(bs.bounty_earned,0) as bounty_earned,
  coalesce(bs.bounty_votes,0) as bounty_votes,
  coalesce(bc.gold_badges,0) as gold_badges,
  coalesce(bc.silver_badges,0) as silver_badges,
  coalesce(bc.bronze_badges,0) as bronze_badges,
  coalesce(bc.tag_badges,0) as tag_badges,
  coalesce(tt.top_tags_by_popularity,'') as top_tags_by_popularity,
  coalesce(tt.tag_mentions,0) as tag_mentions,
  coalesce(cq.closed_q_count,0) as closed_q_count,
  cq.first_closed_date,
  coalesce(ee.edits_made,0) as edits_made,
  coalesce(ee.suggested_applied,0) as suggested_edits_applied,
  coalesce(ee.close_votes_recorded,0) as close_votes_recorded,
  coalesce(lk.links_created,0) as links_created,
  coalesce(lk.marked_duplicate,0) as marked_duplicate,
  coalesce(pq.median_post_score,0) as median_post_score,
  round(cast(coalesce(pq.avg_post_score,0) as numeric),2) as avg_post_score,
  round(cast(coalesce(pq.stddev_post_score,0) as numeric),2) as stddev_post_score,
  coalesce(pq.max_post_score,0) as max_post_score,
  coalesce(pq.min_post_score,0) as min_post_score,
  coalesce(ae.best_month_posts,0) as best_month_posts,
  coalesce(ae.best_month_score,0) as best_month_score,
  cm.pos_posts,
  cm.neg_posts,
  cm.pos_comments,
  cm.neg_comments,
  coalesce(h.times_hot,0) as times_hot,
  coalesce(h.times_unhot,0) as times_unhot,
  coalesce(ro.reopen_votes_recorded,0) as reopen_votes_recorded,
  coalesce(va.upvotes_received,0) as upvotes_received,
  coalesce(va.downvotes_received,0) as downvotes_received,
  round(100.0 * nullif(coalesce(va.upvotes_received,0),0) / nullif(coalesce(va.upvotes_received,0)+coalesce(va.downvotes_received,0),0),2) as upvote_ratio_pct,
  round(100.0 * nullif(coalesce(aa.accepted_answers,0),0) / nullif(ua.answer_count,0),2) as answer_accept_rate_pct,
  cl.avg_comment_len,
  cl.max_comment_len,
  tq.avg_title_len,
  tq.titles_with_question_mark,
  dn.distinct_dupe_targets,
  r.answerer_rank,
  r.asker_rank,
  s.cleaned_location,
  s.display_initial,
  s.maybe_bot_flag,
  case
    when coalesce(ua.total_posts,0) = 0 then 'inactive'
    when coalesce(aa.accepted_answers,0) > 50 or coalesce(bc.gold_badges,0) >= 5 then 'elite'
    when coalesce(va.upvotes_received,0) - coalesce(va.downvotes_received,0) > 100 then 'positive'
    when coalesce(va.downvotes_received,0) > coalesce(va.upvotes_received,0) then 'controversial'
    else 'active'
  end as activity_label
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join accepted_answers aa on aa.user_id = ru.user_id
left join bounty_stats bs on bs.user_id = ru.user_id
left join badge_classes bc on bc.user_id = ru.user_id
left join top_tags tt on tt.user_id = ru.user_id
left join closed_questions cq on cq.user_id = ru.user_id
left join edit_events ee on ee.user_id = ru.user_id
left join linking lk on lk.user_id = ru.user_id
left join post_quality pq on pq.user_id = ru.user_id
left join activity_extremes ae on ae.user_id = ru.user_id
left join correlated_metrics cm on cm.user_id = ru.user_id
left join hotness h on h.user_id = ru.user_id
left join reopen_flow ro on ro.user_id = ru.user_id
left join vote_agg va on va.user_id = ru.user_id
left join comment_length cl on cl.user_id = ru.user_id
left join title_quality tq on tq.user_id = ru.user_id
left join dup_network dn on dn.user_id = ru.user_id
left join rankings r on r.user_id = ru.user_id
left join stringiness s on s.user_id = ru.user_id
left join domain_peers de on de.user_id = ru.user_id
where ru.rn <= 1000
order by
  activity_label desc,
  r.answerer_rank nulls last,
  coalesce(aa.accepted_answers,0) desc,
  ru.reputation desc,
  ru.user_id;