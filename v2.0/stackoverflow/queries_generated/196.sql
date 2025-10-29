-- {"query": "196.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2670} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.location,
         u.creationdate,
         u.upvotes,
         u.downvotes,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tag_exploded as (
  select p.id as post_id,
         lower(trim(both ' ' from t.tag)) as tagname
  from posts p
  cross join lateral unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as t(tag)
  where p.posttypeid = 1
    and p.tags is not null
),
hot_questions as (
  select q.id as question_id,
         q.owneruserid as owner_id,
         q.score,
         q.viewcount,
         q.answercount,
         q.creationdate,
         q.closeddate,
         q.title,
         q.tags,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes
  from posts q
  left join votes v on v.postid = q.id and v.votetypeid in (2,3)
  where q.posttypeid = 1
    and q.creationdate >= (select max(creationdate) - interval '180 days' from posts)
  group by q.id, q.owneruserid, q.score, q.viewcount, q.answercount, q.creationdate, q.closeddate, q.title, q.tags
),
dup_clusters as (
  select pl.relatedpostid as canonical_id,
         count(*) as dup_count,
         min(pl.creationdate) as first_dup_date,
         max(pl.creationdate) as last_dup_date
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.relatedpostid
),
user_activity as (
  select u.id as user_id,
         count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
         count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
         count(distinct c.id) as c_count,
         count(distinct b.id) as badge_count,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         max(coalesce(p.lastactivitydate, u.lastaccessdate)) as last_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join badges b on b.userid = u.id
  group by u.id
),
question_quality as (
  select hq.question_id,
         hq.owner_id,
         hq.score,
         hq.viewcount,
         hq.answercount,
         hq.net_votes,
         coalesce(dc.dup_count, 0) as dup_count,
         case when hq.closeddate is not null then 1 else 0 end as is_closed,
         percentile_cont(0.5) within group (order by hq.viewcount) over () as p50_views,
         avg(hq.score) over () as avg_score_all,
         rank() over (order by hq.net_votes desc nulls last, hq.viewcount desc nulls last) as rnk_hotness,
         dense_rank() over (order by coalesce(dc.dup_count,0) desc, hq.viewcount desc nulls last) as rnk_dup_pop
  from hot_questions hq
  left join dup_clusters dc on dc.canonical_id = hq.question_id
),
tag_stats as (
  select te.tagname,
         count(distinct te.post_id) as q_with_tag,
         sum(hq.viewcount) as total_views,
         sum(hq.score) as total_score,
         avg(hq.score)::numeric(12,4) as avg_score,
         sum(case when qq.is_closed = 1 then 1 else 0 end) as closed_count,
         sum(qq.dup_count) as total_dups
  from tag_exploded te
  join hot_questions hq on hq.question_id = te.post_id
  join question_quality qq on qq.question_id = te.post_id
  group by te.tagname
),
recent_commenter_sentiment as (
  select p.id as post_id,
         sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count,
         sum(case when position('wrong' in lower(c.text)) > 0 then 1 else 0 end) as wrong_count,
         sum(case when position('please' in lower(c.text)) > 0 then 1 else 0 end) as please_count,
         count(*) as total_comments,
         max(c.creationdate) as last_comment_date
  from posts p
  left join comments c on c.postid = p.id
  where p.posttypeid in (1,2)
    and p.creationdate >= (select max(creationdate) - interval '90 days' from posts)
  group by p.id
),
owner_meta as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         ua.q_count,
         ua.a_count,
         ua.c_count,
         ua.badge_count,
         ua.gold_badges,
         ua.silver_badges,
         ua.bronze_badges,
         ua.last_activity,
         coalesce(u.location, 'Unknown') as location_norm,
         case
           when u.websiteurl is null or trim(u.websiteurl) = '' then 'none'
           when u.websiteurl ilike 'http%' then 'url'
           else 'other'
         end as website_kind
  from users u
  join user_activity ua on ua.user_id = u.id
),
accepted_answer_latency as (
  select q.id as question_id,
         a.id as answer_id,
         a.owneruserid as answerer_id,
         extract(epoch from (a.creationdate - q.creationdate))/3600.0 as hours_to_answer,
         row_number() over (partition by q.id order by a.score desc nulls last, a.creationdate asc) as rn_best_guess
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
dominant_tag as (
  select te.post_id,
         te.tagname,
         row_number() over (partition by te.post_id order by ts.q_with_tag desc, te.tagname) as rn
  from tag_exploded te
  join tag_stats ts on ts.tagname = te.tagname
),
question_flags as (
  select qq.question_id,
         (case when qq.viewcount >= qq.p50_views then 1 else 0 end) as is_high_view,
         (case when qq.score >= qq.avg_score_all then 1 else 0 end) as is_high_score,
         (case when qq.rnk_hotness <= 100 then 1 else 0 end) as is_top100_hot,
         (case when qq.rnk_dup_pop <= 50 then 1 else 0 end) as is_dup_cluster
  from question_quality qq
),
post_history_meta as (
  select ph.postid,
         sum(case when ph.posthistorytypeid in (4,5,6) then 1 else 0 end) as edit_events,
         sum(case when ph.posthistorytypeid in (10) then 1 else 0 end) as close_events,
         sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
         max(ph.creationdate) as last_history_date,
         count(*) as total_history_events,
         sum(case when ph.posthistorytypeid in (10) and ph.comment ~ '^[0-9]+$' then 1 else 0 end) as close_with_reason
  from posthistory ph
  group by ph.postid
),
license_mix as (
  select p.id as post_id,
         coalesce(nullif(p.contentlicense, ''), 'unknown') as license_name,
         row_number() over (partition by p.id order by p.contentlicense nulls last) as rn
  from posts p
),
cte_union as (
  select question_id as entity_id, 'question' as entity_type from hot_questions
  union
  select id as entity_id, 'answer' as entity_type from posts where posttypeid = 2
  union all
  select postid as entity_id, 'commented' as entity_type from comments
),
bench as (
  select
    qq.question_id,
    om.user_id as owner_id,
    om.displayname as owner_name,
    om.reputation as owner_reputation,
    om.q_count, om.a_count, om.c_count,
    om.badge_count, om.gold_badges, om.silver_badges, om.bronze_badges,
    qq.score, qq.viewcount, qq.answercount, qq.net_votes,
    qf.is_high_view, qf.is_high_score, qf.is_top100_hot, qf.is_dup_cluster,
    coalesce(dc.dup_count, 0) as dup_cluster_size,
    d.tagname as dominant_tag,
    ts.q_with_tag as dominant_tag_qcount,
    ts.total_views as dominant_tag_views,
    ts.avg_score as dominant_tag_avgscore,
    rcs.thanks_count, rcs.wrong_count, rcs.please_count, rcs.total_comments,
    phm.edit_events, phm.close_events, phm.reopen_events, phm.total_history_events,
    aal.hours_to_answer as first_answer_hours,
    case when aal.rn_best_guess = 1 then aal.hours_to_answer end as best_answer_eta_hours,
    lm.license_name,
    extract(epoch from (coalesce(phm.last_history_date, qq.creationdate) - qq.creationdate))/3600.0 as hours_to_last_edit,
    case when qq.is_closed = 1 then 'closed' else 'open' end as status,
    (qq.net_votes + greatest(qq.viewcount/100::int,0)) as composite_score,
    row_number() over (order by (qq.net_votes + greatest(qq.viewcount/100::int,0)) desc, qq.score desc) as rank_composite,
    count(*) over () as total_rows,
    (select count(*) from cte_union cu where cu.entity_type = 'question') as total_questions,
    (select count(*) from cte_union cu where cu.entity_type = 'answer') as total_answers
  from question_quality qq
  left join owner_meta om on om.user_id = qq.owner_id
  left join dup_clusters dc on dc.canonical_id = qq.question_id
  left join dominant_tag d on d.post_id = qq.question_id and d.rn = 1
  left join tag_stats ts on ts.tagname = d.tagname
  left join recent_commenter_sentiment rcs on rcs.post_id = qq.question_id
  left join post_history_meta phm on phm.postid = qq.question_id
  left join accepted_answer_latency aal on aal.question_id = qq.question_id and aal.rn_best_guess = 1
  left join license_mix lm on lm.post_id = qq.question_id and lm.rn = 1
)
select *
from bench b
where (b.status = 'open' or (b.status = 'closed' and b.dup_cluster_size >= 1))
  and coalesce(b.owner_reputation, 0) >= 0
  and (b.thanks_count >= b.wrong_count or b.total_comments is null)
  and (b.dominant_tag is null or length(b.dominant_tag) between 1 and 35)
  and (b.license_name is distinct from 'unknown' or b.edit_events > 0)
  and (
       b.rank_composite <= 250
       or (
          b.rank_composite > 250
          and b.is_top100_hot = 1
          and (b.is_high_view = 1 or b.is_high_score = 1)
       )
  )
order by b.rank_composite, b.question_id
limit 500;