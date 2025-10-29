-- {"query": "761.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2848} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
         dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
),
active_questions as (
  select p.id as qid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.acceptedanswerid,
         p.closeddate,
         case when p.closeddate is null then 1 else 0 end as is_open
  from posts p
  where p.posttypeid = 1
),
tag_split as (
  select q.qid,
         lower(trim(both ' ' from t.tag)) as tagname
  from active_questions q
  cross join lateral unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as t(tag)
),
tag_meta as (
  select ts.qid,
         count(*) as tag_count,
         sum(case when tg.ismoderatoronly then 1 else 0 end) as modonly_tags,
         sum(case when tg.isrequired then 1 else 0 end) as required_tags
  from tag_split ts
  left join tags tg on tg.tagname = ts.tagname
  group by ts.qid
),
question_votes as (
  select v.postid as qid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid
),
answer_stats as (
  select a.parentid as qid,
         count(*) as answers,
         max(a.score) as max_answer_score,
         sum(case when a.score > 0 then 1 else 0 end) as positive_answers
  from posts a
  where a.posttypeid = 2
  group by a.parentid
),
accepted_answer_age as (
  select q.id as qid,
         aa.id as aid,
         extract(epoch from (aa.creationdate - q.creationdate))::bigint as seconds_to_accept
  from posts q
  join posts aa on aa.id = q.acceptedanswerid
  where q.posttypeid = 1 and q.acceptedanswerid is not null
),
comment_activity as (
  select c.postid as qid,
         count(*) as comments,
         max(c.creationdate) as last_comment_at,
         sum(case when c.score > 0 then 1 else 0 end) as upvoted_comments
  from comments c
  group by c.postid
),
close_events as (
  select ph.postid as qid,
         min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
         max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
         max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_count,
         string_agg(distinct case when ph.posthistorytypeid = 10 then ph.comment end, ',') as close_reason_ids
  from posthistory ph
  join posts p on p.id = ph.postid and p.posttypeid = 1
  group by ph.postid
),
dup_links as (
  select pl.postid as qid,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
user_badge_summary as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as golds,
         sum(case when b.class = 2 then 1 else 0 end) as silvers,
         sum(case when b.class = 3 then 1 else 0 end) as bronzes,
         count(*) as total_badges,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
question_quality as (
  select q.qid,
         q.owneruserid,
         q.creationdate,
         q.score,
         q.viewcount,
         q.title,
         tm.tag_count,
         tm.modonly_tags,
         tm.required_tags,
         coalesce(qv.upvotes,0) as upvotes,
         coalesce(qv.downvotes,0) as downvotes,
         coalesce(qv.favorites,0) as favorites,
         coalesce(qv.bounty_total,0) as bounty_total,
         coalesce(ans.answers,0) as answers,
         coalesce(ans.max_answer_score,0) as max_answer_score,
         coalesce(ans.positive_answers,0) as positive_answers,
         coalesce(aa.seconds_to_accept, null) as seconds_to_accept,
         coalesce(ca.comments,0) as comments,
         ca.last_comment_at,
         coalesce(ce.close_count,0) as close_count,
         ce.first_closed_at,
         ce.last_closed_at,
         ce.last_reopened_at,
         coalesce(dl.duplicate_links,0) as duplicate_links,
         coalesce(dl.related_links,0) as related_links
  from active_questions q
  left join tag_meta tm on tm.qid = q.qid
  left join question_votes qv on qv.qid = q.qid
  left join answer_stats ans on ans.qid = q.qid
  left join accepted_answer_age aa on aa.qid = q.qid
  left join comment_activity ca on ca.qid = q.qid
  left join close_events ce on ce.qid = q.qid
  left join dup_links dl on dl.qid = q.qid
),
owner_enriched as (
  select qq.*,
         u.displayname as owner_name,
         u.reputation as owner_rep,
         u.creationdate as user_created,
         u.location as owner_location,
         ub.total_badges,
         ub.golds,
         ub.silvers,
         ub.bronzes,
         ub.last_badge_at,
         ru.recency_rank as user_recency_rank
  from question_quality qq
  left join users u on u.id = qq.owneruserid
  left join user_badge_summary ub on ub.userid = qq.owneruserid
  left join recent_users ru on ru.user_id = qq.owneruserid
),
scored as (
  select oe.*,
         -- complex scoring with null handling and non-linear transforms
         (
           coalesce(oe.upvotes,0)*3
           - coalesce(oe.downvotes,0)*2
           + least(coalesce(oe.favorites,0), 50)
           + ln(1 + greatest(oe.viewcount,0))::numeric
           + case when oe.answers >= 1 then 5 else 0 end
           + case when oe.max_answer_score >= 5 then 3 else 0 end
           + case when oe.seconds_to_accept is not null then greatest(10 - (oe.seconds_to_accept/3600.0)::numeric, 0)::numeric else 0 end
           - coalesce(oe.close_count,0)*5
           - coalesce(oe.duplicate_links,0)*4
           + coalesce(oe.related_links,0)*0.5
           + coalesce(oe.bounty_total,0)*0.1
           + coalesce(ub_bias.total_badges,0)*0.2
         )::numeric as quality_score,
         case
           when oe.close_count > 0 and oe.last_reopened_at is null then 'closed'
           when oe.close_count > 0 and oe.last_reopened_at is not null and coalesce(oe.last_closed_at, timestamp 'epoch') > oe.last_reopened_at then 'closed'
           when oe.close_count > 0 then 'reopened'
           else 'open'
         end as close_state
  from owner_enriched oe
  left join user_badge_summary ub_bias on ub_bias.userid = oe.owneruserid
),
ranked as (
  select s.*,
         row_number() over (order by s.quality_score desc nulls last, s.viewcount desc nulls last, s.creationdate desc) as rn,
         ntile(10) over (order by s.quality_score desc nulls last) as decile,
         avg(s.quality_score) over () as avg_quality_overall,
         avg(s.quality_score) over (partition by coalesce(s.owner_location,'n/a')) as avg_quality_by_location
  from scored s
),
location_outliers as (
  select coalesce(owner_location,'n/a') as owner_location,
         avg(quality_score) as loc_avg,
         stddev_pop(quality_score) as loc_std
  from ranked
  group by coalesce(owner_location,'n/a')
),
final_set as (
  select r.*,
         lo.loc_avg,
         lo.loc_std,
         case when r.quality_score is not null and lo.loc_std is not null and lo.loc_std > 0
              then (r.quality_score - lo.loc_avg)/lo.loc_std
              else null end as z_loc,
         case when r.quality_score >= r.avg_quality_overall then 1 else 0 end as above_global_avg
  from ranked r
  left join location_outliers lo on coalesce(lo.owner_location,'n/a') = coalesce(r.owner_location,'n/a')
),
reopened_events as (
  select ph.postid as qid,
         count(*) as reopen_events
  from posthistory ph
  where ph.posthistorytypeid = 11
  group by ph.postid
),
closed_vs_reopened as (
  select ce.qid,
         ce.close_count,
         coalesce(re.reopen_events,0) as reopen_events
  from close_events ce
  left join reopened_events re on re.qid = ce.qid
),
slices as (
  select f.*,
         cvr.reopen_events,
         case
           when f.tag_count is null or f.tag_count = 0 then 'untagged'
           when f.tag_count = 1 then 'single-tag'
           when f.tag_count between 2 and 3 then 'few-tags'
           else 'many-tags'
         end as tag_bucket,
         case when extract(dow from f.creationdate) in (0,6) then 'weekend' else 'weekday' end as weekday_flag,
         case when f.seconds_to_accept is null then 'no-accept' else 'accepted' end as accept_flag
  from final_set f
  left join closed_vs_reopened cvr on cvr.qid = f.qid
),
top_per_bucket as (
  select s.*,
         row_number() over (partition by s.tag_bucket, s.weekday_flag, s.accept_flag order by s.quality_score desc nulls last) as bucket_rank
  from slices s
)
select
  tp.qid,
  tp.title,
  coalesce(tp.owner_name, '[unknown]') as owner_name,
  tp.owner_rep,
  tp.owner_location,
  tp.user_recency_rank,
  tp.creationdate,
  tp.viewcount,
  tp.upvotes,
  tp.downvotes,
  tp.favorites,
  tp.answers,
  tp.max_answer_score,
  tp.comments,
  tp.duplicate_links,
  tp.related_links,
  tp.tag_count,
  tp.modonly_tags,
  tp.required_tags,
  tp.close_state,
  tp.close_count,
  tp.reopen_events,
  tp.seconds_to_accept,
  round(tp.quality_score::numeric, 3) as quality_score,
  tp.decile,
  round(tp.avg_quality_overall::numeric, 3) as avg_quality_overall,
  round(tp.avg_quality_by_location::numeric, 3) as avg_quality_by_location,
  round(tp.z_loc::numeric, 3) as z_score_location,
  tp.tag_bucket,
  tp.weekday_flag,
  tp.accept_flag
from top_per_bucket tp
where tp.bucket_rank <= 5
  and (
    tp.quality_score is distinct from null
    or tp.viewcount > 0
  )
  and (
    tp.owner_rep >= coalesce((
      select percentile_cont(0.25) within group (order by reputation)
      from users
    ), 0)
    or tp.answers >= 1
  )
  and not exists (
    select 1
    from postlinks pl
    where pl.postid = tp.qid
      and pl.linktypeid = 3
      and pl.relatedpostid = tp.qid
  )
order by tp.tag_bucket, tp.weekday_flag, tp.accept_flag, tp.quality_score desc, tp.viewcount desc;